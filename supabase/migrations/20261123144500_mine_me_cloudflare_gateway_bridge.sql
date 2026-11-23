-- Signed Cloudflare Durable Object bridge for MINE-ME's browser-mining gateway.
-- The browser never receives this signing secret. Cloudflare's gateway signs each
-- command and this narrowly scoped RPC verifies it before reading/writing mining data.

create table if not exists private.mine_me_gateway_request_nonces (
  nonce uuid primary key,
  expires_at timestamptz not null
);

revoke all on table private.mine_me_gateway_request_nonces from public, anon, authenticated, service_role;

create or replace function public.mine_me_gateway_command(
  p_action text,
  p_payload text,
  p_timestamp bigint,
  p_nonce uuid,
  p_signature text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_secret text;
  v_expected text;
  v_canonical text;
  v_payload jsonb;
  v_user_id uuid;
  v_device_id uuid;
  v_gateway_session_id uuid;
  v_worker_code text;
  v_consent_version text;
  v_intensity integer;
  v_max_intensity integer := 80;
  v_mining_enabled boolean := false;
  v_emergency_pause boolean := true;
  v_account_status text;
  v_has_consent boolean := false;
  v_device_status text;
  v_device_worker_code text;
  v_device_intensity integer;
  v_active_session_id uuid;
  v_pool_share_id text;
  v_accepted boolean;
  v_rows integer;
  v_hashrate numeric;
  v_hashes bigint;
  v_sample_seconds numeric;
begin
  if p_action is null or p_action not in ('authorize', 'activate', 'heartbeat', 'offline', 'share', 'telemetry') then
    raise exception 'Unsupported gateway action.' using errcode = '22023';
  end if;
  if p_payload is null or length(p_payload) > 8192 or p_timestamp is null
     or p_nonce is null or p_signature is null or p_signature !~ '^[0-9a-f]{64}
    raise exception 'Malformed gateway command.' using errcode = '22023';
  end if;
  if abs(extract(epoch from clock_timestamp())::bigint - p_timestamp) > 120 then
    raise exception 'Gateway command expired.' using errcode = '28000';
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'mine_me_gateway_hmac'
  limit 1;

  if v_secret is null or length(v_secret) < 32 then
    raise exception 'Gateway signing is not configured.' using errcode = '55000';
  end if;

  v_canonical := p_action || E'\n' || p_timestamp::text || E'\n' || p_nonce::text || E'\n' || p_payload;
  v_expected := encode(
    extensions.hmac(convert_to(v_canonical, 'UTF8'), convert_to(v_secret, 'UTF8'), 'sha256'),
    'hex'
  );
  if v_expected <> p_signature then
    raise exception 'Invalid gateway signature.' using errcode = '28000';
  end if;

  insert into private.mine_me_gateway_request_nonces (nonce, expires_at)
  values (p_nonce, to_timestamp(p_timestamp) + interval '5 minutes')
  on conflict do nothing;
  if not found then
    raise exception 'Gateway command replay detected.' using errcode = '28000';
  end if;
  delete from private.mine_me_gateway_request_nonces where expires_at < clock_timestamp();

  begin
    v_payload := p_payload::jsonb;
    v_user_id := (v_payload->>'sub')::uuid;
    v_device_id := (v_payload->>'deviceId')::uuid;
    v_worker_code := v_payload->>'workerCode';
    v_consent_version := v_payload->>'consentVersion';
    v_intensity := (v_payload->>'intensityPercent')::integer;
    if p_action <> 'authorize' then
      v_gateway_session_id := (v_payload->>'gatewaySessionId')::uuid;
    end if;
  exception when others then
    raise exception 'Invalid gateway command payload.' using errcode = '22023';
  end;

  if v_user_id is null or v_device_id is null or
     v_worker_code !~ '^MM-[0-9A-F]{32}$' or
     v_consent_version <> '2026-11-19-v1' or
     v_intensity < 1 or v_intensity > 80 then
    raise exception 'Invalid mining session claims.' using errcode = '22023';
  end if;

  select p.account_status, p.consent_version, (p.consented_at is not null)
    into v_account_status, v_consent_version, v_has_consent
  from public.profiles p
  where p.id = v_user_id;
  if not found or v_account_status <> 'active' or
     v_consent_version <> (v_payload->>'consentVersion') or not v_has_consent then
    return jsonb_build_object('authorized', false, 'reason', 'member_inactive_or_consent_missing');
  end if;

  select d.status, d.worker_code, d.intensity_percent, d.active_session_id
    into v_device_status, v_device_worker_code, v_device_intensity, v_active_session_id
  from public.devices d
  where d.id = v_device_id and d.user_id = v_user_id;
  if not found or v_device_worker_code <> v_worker_code then
    return jsonb_build_object('authorized', false, 'reason', 'device_not_found');
  end if;

  select coalesce((value #>> '{}')::boolean, false)
    into v_mining_enabled
  from public.platform_settings where key = 'mining_enabled';
  select coalesce((value #>> '{}')::boolean, true)
    into v_emergency_pause
  from public.platform_settings where key = 'global_emergency_pause';
  select least(80, greatest(1, coalesce((value #>> '{}')::integer, 80)))
    into v_max_intensity
  from public.platform_settings where key = 'global_max_intensity_percent';

  if not coalesce(v_mining_enabled, false) or coalesce(v_emergency_pause, true) then
    return jsonb_build_object('authorized', false, 'reason', 'platform_paused');
  end if;
  if v_intensity > least(v_device_intensity, v_max_intensity) then
    return jsonb_build_object('authorized', false, 'reason', 'intensity_limit_changed');
  end if;

  if p_action = 'authorize' then
    if v_device_status not in ('enrolled', 'offline', 'running') then
      return jsonb_build_object('authorized', false, 'reason', 'device_not_enrolled');
    end if;
    if v_device_status = 'running' and v_active_session_id is not null then
      return jsonb_build_object('authorized', false, 'reason', 'device_already_has_session');
    end if;
    return jsonb_build_object('authorized', true, 'maxIntensityPercent', v_max_intensity);
  end if;

  if v_gateway_session_id is null then
    raise exception 'Missing gateway session identifier.' using errcode = '22023';
  end if;

  if p_action = 'activate' then
    if v_device_status not in ('enrolled', 'offline') then
      return jsonb_build_object('authorized', false, 'reason', 'device_not_enrolled');
    end if;
    update public.devices
      set status = 'running',
          active_session_id = v_gateway_session_id,
          last_seen_at = clock_timestamp()
    where id = v_device_id and user_id = v_user_id
      and status in ('enrolled', 'offline')
    returning status, intensity_percent, active_session_id
      into v_device_status, v_device_intensity, v_active_session_id;
    if not found or v_device_status <> 'running' or
       v_active_session_id <> v_gateway_session_id or
       v_device_intensity < v_intensity then
      return jsonb_build_object('authorized', false, 'reason', 'device_activation_failed');
    end if;
    return jsonb_build_object('authorized', true, 'status', 'running');
  end if;

  if p_action = 'heartbeat' then
    if v_device_status <> 'running' or v_active_session_id <> v_gateway_session_id then
      return jsonb_build_object('authorized', false, 'reason', 'device_session_revoked');
    end if;
    update public.devices set last_seen_at = clock_timestamp()
    where id = v_device_id and user_id = v_user_id
      and status = 'running' and active_session_id = v_gateway_session_id;
    return jsonb_build_object('authorized', true);
  end if;

  if p_action = 'offline' then
    update public.devices
      set status = 'offline', active_session_id = null, last_seen_at = clock_timestamp()
    where id = v_device_id and user_id = v_user_id
      and status = 'running' and active_session_id = v_gateway_session_id;
    get diagnostics v_rows = row_count;
    return jsonb_build_object('updated', v_rows = 1);
  end if;

  if v_device_status <> 'running' or v_active_session_id <> v_gateway_session_id then
    return jsonb_build_object('authorized', false, 'reason', 'device_session_revoked');
  end if;

  if p_action = 'share' then
    v_pool_share_id := v_payload->>'poolShareId';
    v_accepted := (v_payload->>'accepted')::boolean;
    if v_pool_share_id is null or length(v_pool_share_id) < 8 or length(v_pool_share_id) > 256
       or v_accepted is null then
      raise exception 'Invalid pool share record.' using errcode = '22023';
    end if;
    insert into public.mining_share_ledger (
      device_id, pool_share_id, accepted, difficulty, verified_at
    ) values (
      v_device_id, v_pool_share_id, v_accepted, null, clock_timestamp()
    ) on conflict (pool_share_id) do nothing;
    get diagnostics v_rows = row_count;
    return jsonb_build_object('recorded', v_rows = 1, 'accepted', v_accepted);
  end if;

  if p_action = 'telemetry' then
    v_hashrate := (v_payload->>'hashesPerSecond')::numeric;
    v_hashes := (v_payload->>'hashesComputed')::bigint;
    v_sample_seconds := (v_payload->>'sampleSeconds')::numeric;
    if v_hashrate is null or v_hashrate < 0 or v_hashrate > 1000000
       or v_hashes is null or v_hashes < 0
       or v_sample_seconds is null or v_sample_seconds < 0.5 or v_sample_seconds > 60 then
      raise exception 'Invalid browser telemetry.' using errcode = '22023';
    end if;
    insert into public.device_telemetry (
      device_id, reported_hashrate, hashes_computed, sample_seconds, measured_at, received_at
    ) values (
      v_device_id, v_hashrate, v_hashes, v_sample_seconds, clock_timestamp(), clock_timestamp()
    )
    on conflict (device_id) do update set
      reported_hashrate = excluded.reported_hashrate,
      hashes_computed = excluded.hashes_computed,
      sample_seconds = excluded.sample_seconds,
      measured_at = excluded.measured_at,
      received_at = excluded.received_at;
    return jsonb_build_object('recorded', true);
  end if;

  raise exception 'Unhandled gateway action.' using errcode = '22023';
end;
$function$;

revoke all on function public.mine_me_gateway_command(text, text, bigint, uuid, text) from public, anon, authenticated;
grant execute on function public.mine_me_gateway_command(text, text, bigint, uuid, text) to anon, authenticated;

comment on function public.mine_me_gateway_command(text, text, bigint, uuid, text)
is 'Private HMAC-authenticated bridge for the MINE-ME Cloudflare pool gateway. Never called directly by browsers.';
 then
    raise exception 'Malformed gateway command.' using errcode = '22023';
  end if;
  if abs(extract(epoch from clock_timestamp())::bigint - p_timestamp) > 120 then
    raise exception 'Gateway command expired.' using errcode = '28000';
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'mine_me_gateway_hmac'
  limit 1;

  if v_secret is null or length(v_secret) < 32 then
    raise exception 'Gateway signing is not configured.' using errcode = '55000';
  end if;

  v_canonical := p_action || E'\n' || p_timestamp::text || E'\n' || p_nonce::text || E'\n' || p_payload;
  v_expected := encode(
    extensions.hmac(convert_to(v_canonical, 'UTF8'), convert_to(v_secret, 'UTF8'), 'sha256'),
    'hex'
  );
  if v_expected <> p_signature then
    raise exception 'Invalid gateway signature.' using errcode = '28000';
  end if;

  insert into private.mine_me_gateway_request_nonces (nonce, expires_at)
  values (p_nonce, to_timestamp(p_timestamp) + interval '5 minutes')
  on conflict do nothing;
  if not found then
    raise exception 'Gateway command replay detected.' using errcode = '28000';
  end if;
  delete from private.mine_me_gateway_request_nonces where expires_at < clock_timestamp();

  begin
    v_payload := p_payload::jsonb;
    v_user_id := (v_payload->>'sub')::uuid;
    v_device_id := (v_payload->>'deviceId')::uuid;
    v_worker_code := v_payload->>'workerCode';
    v_consent_version := v_payload->>'consentVersion';
    v_intensity := (v_payload->>'intensityPercent')::integer;
    if p_action <> 'authorize' then
      v_gateway_session_id := (v_payload->>'gatewaySessionId')::uuid;
    end if;
  exception when others then
    raise exception 'Invalid gateway command payload.' using errcode = '22023';
  end;

  if v_user_id is null or v_device_id is null or
     v_worker_code !~ '^MM-[0-9A-F]{32}$' or
     v_consent_version <> '2026-11-19-v1' or
     v_intensity < 1 or v_intensity > 80 then
    raise exception 'Invalid mining session claims.' using errcode = '22023';
  end if;

  select p.account_status, p.consent_version, (p.consented_at is not null)
    into v_account_status, v_consent_version, v_has_consent
  from public.profiles p
  where p.id = v_user_id;
  if not found or v_account_status <> 'active' or
     v_consent_version <> (v_payload->>'consentVersion') or not v_has_consent then
    return jsonb_build_object('authorized', false, 'reason', 'member_inactive_or_consent_missing');
  end if;

  select d.status, d.worker_code, d.intensity_percent, d.active_session_id
    into v_device_status, v_device_worker_code, v_device_intensity, v_active_session_id
  from public.devices d
  where d.id = v_device_id and d.user_id = v_user_id;
  if not found or v_device_worker_code <> v_worker_code then
    return jsonb_build_object('authorized', false, 'reason', 'device_not_found');
  end if;

  select coalesce((value #>> '{}')::boolean, false)
    into v_mining_enabled
  from public.platform_settings where key = 'mining_enabled';
  select coalesce((value #>> '{}')::boolean, true)
    into v_emergency_pause
  from public.platform_settings where key = 'global_emergency_pause';
  select least(80, greatest(1, coalesce((value #>> '{}')::integer, 80)))
    into v_max_intensity
  from public.platform_settings where key = 'global_max_intensity_percent';

  if not coalesce(v_mining_enabled, false) or coalesce(v_emergency_pause, true) then
    return jsonb_build_object('authorized', false, 'reason', 'platform_paused');
  end if;
  if v_intensity > least(v_device_intensity, v_max_intensity) then
    return jsonb_build_object('authorized', false, 'reason', 'intensity_limit_changed');
  end if;

  if p_action = 'authorize' then
    if v_device_status not in ('enrolled', 'offline', 'running') then
      return jsonb_build_object('authorized', false, 'reason', 'device_not_enrolled');
    end if;
    if v_device_status = 'running' and v_active_session_id is not null then
      return jsonb_build_object('authorized', false, 'reason', 'device_already_has_session');
    end if;
    return jsonb_build_object('authorized', true, 'maxIntensityPercent', v_max_intensity);
  end if;

  if v_gateway_session_id is null then
    raise exception 'Missing gateway session identifier.' using errcode = '22023';
  end if;

  if p_action = 'activate' then
    if v_device_status not in ('enrolled', 'offline') then
      return jsonb_build_object('authorized', false, 'reason', 'device_not_enrolled');
    end if;
    update public.devices
      set status = 'running',
          active_session_id = v_gateway_session_id,
          last_seen_at = clock_timestamp()
    where id = v_device_id and user_id = v_user_id
      and status in ('enrolled', 'offline')
    returning status, intensity_percent, active_session_id
      into v_device_status, v_device_intensity, v_active_session_id;
    if not found or v_device_status <> 'running' or
       v_active_session_id <> v_gateway_session_id or
       v_device_intensity < v_intensity then
      return jsonb_build_object('authorized', false, 'reason', 'device_activation_failed');
    end if;
    return jsonb_build_object('authorized', true, 'status', 'running');
  end if;

  if p_action = 'heartbeat' then
    if v_device_status <> 'running' or v_active_session_id <> v_gateway_session_id then
      return jsonb_build_object('authorized', false, 'reason', 'device_session_revoked');
    end if;
    update public.devices set last_seen_at = clock_timestamp()
    where id = v_device_id and user_id = v_user_id
      and status = 'running' and active_session_id = v_gateway_session_id;
    return jsonb_build_object('authorized', true);
  end if;

  if p_action = 'offline' then
    update public.devices
      set status = 'offline', active_session_id = null, last_seen_at = clock_timestamp()
    where id = v_device_id and user_id = v_user_id
      and status = 'running' and active_session_id = v_gateway_session_id;
    get diagnostics v_rows = row_count;
    return jsonb_build_object('updated', v_rows = 1);
  end if;

  if v_device_status <> 'running' or v_active_session_id <> v_gateway_session_id then
    return jsonb_build_object('authorized', false, 'reason', 'device_session_revoked');
  end if;

  if p_action = 'share' then
    v_pool_share_id := v_payload->>'poolShareId';
    v_accepted := (v_payload->>'accepted')::boolean;
    if v_pool_share_id is null or length(v_pool_share_id) < 8 or length(v_pool_share_id) > 256
       or v_accepted is null then
      raise exception 'Invalid pool share record.' using errcode = '22023';
    end if;
    insert into public.mining_share_ledger (
      device_id, pool_share_id, accepted, difficulty, verified_at
    ) values (
      v_device_id, v_pool_share_id, v_accepted, null, clock_timestamp()
    ) on conflict (pool_share_id) do nothing;
    get diagnostics v_rows = row_count;
    return jsonb_build_object('recorded', v_rows = 1, 'accepted', v_accepted);
  end if;

  if p_action = 'telemetry' then
    v_hashrate := (v_payload->>'hashesPerSecond')::numeric;
    v_hashes := (v_payload->>'hashesComputed')::bigint;
    v_sample_seconds := (v_payload->>'sampleSeconds')::numeric;
    if v_hashrate is null or v_hashrate < 0 or v_hashrate > 1000000
       or v_hashes is null or v_hashes < 0
       or v_sample_seconds is null or v_sample_seconds < 0.5 or v_sample_seconds > 60 then
      raise exception 'Invalid browser telemetry.' using errcode = '22023';
    end if;
    insert into public.device_telemetry (
      device_id, reported_hashrate, hashes_computed, sample_seconds, measured_at, received_at
    ) values (
      v_device_id, v_hashrate, v_hashes, v_sample_seconds, clock_timestamp(), clock_timestamp()
    )
    on conflict (device_id) do update set
      reported_hashrate = excluded.reported_hashrate,
      hashes_computed = excluded.hashes_computed,
      sample_seconds = excluded.sample_seconds,
      measured_at = excluded.measured_at,
      received_at = excluded.received_at;
    return jsonb_build_object('recorded', true);
  end if;

  raise exception 'Unhandled gateway action.' using errcode = '22023';
end;
$function$;

revoke all on function public.mine_me_gateway_command(text, text, bigint, uuid, text) from public, anon, authenticated;
grant execute on function public.mine_me_gateway_command(text, text, bigint, uuid, text) to anon, authenticated;

comment on function public.mine_me_gateway_command(text, text, bigint, uuid, text)
is 'Private HMAC-authenticated bridge for the MINE-ME Cloudflare pool gateway. Never called directly by browsers.';
