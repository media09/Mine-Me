import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "./actions";
import CopyReferralLink from "./copy-referral-link";
import AutoEnrollDevice from "./auto-enroll-device";
import DeviceControl from "./device-control";

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/mineme/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name, referral_code, role, consented_at, account_status, referral_enabled")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.account_status === "suspended") redirect("/mineme/account-suspended");

  const { data: devices } = await supabase
    .from("devices")
    .select("id, worker_code, label, status, intensity_percent, last_seen_at")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  const { data: referrals } = await supabase
    .from("referrals")
    .select("id, created_at")
    .eq("inviter_id", user.id)
    .order("created_at", { ascending: false });

  const { data: platformSettings } = await supabase
    .from("platform_settings")
    .select("key, value")
    .in("key", ["mining_enabled", "global_emergency_pause", "global_max_intensity_percent"]);

  const deviceIds = (devices ?? []).map((device) => device.id);
  const [shareResult, eventResult, telemetryResult] = deviceIds.length
    ? await Promise.all([
        supabase.from("mining_share_ledger")
          .select("id, pool_share_id, accepted, difficulty, verified_at")
          .in("device_id", deviceIds)
          .order("verified_at", { ascending: false })
          .limit(25),
        supabase.from("device_events")
          .select("id, event_type, details, created_at, device_id")
          .in("device_id", deviceIds)
          .order("created_at", { ascending: false })
          .limit(25),
        supabase.from("device_telemetry")
          .select("device_id, reported_hashrate, hashes_computed, sample_seconds, measured_at, received_at")
          .in("device_id", deviceIds)
          .order("received_at", { ascending: false }),
      ])
    : [{ data: [] }, { data: [] }, { data: [] }];

  const verifiedShares = shareResult.data ?? [];
  const deviceEvents = eventResult.data ?? [];
  const deviceTelemetry = telemetryResult.data ?? [];
  const acceptedShareCount = verifiedShares.filter((share) => share.accepted).length;
  const setting = (key: string) => platformSettings?.find((row) => row.key === key)?.value;
  const miningEnabled = setting("mining_enabled") === true;
  const emergencyPause = setting("global_emergency_pause") !== false;
  const platformAllowsMining = miningEnabled && !emergencyPause;
  const maxIntensityValue = Number(setting("global_max_intensity_percent") ?? 80);
  const maxIntensityPercent = Number.isFinite(maxIntensityValue)
    ? Math.min(80, Math.max(1, Math.trunc(maxIntensityValue)))
    : 80;

  const siteUrl = (process.env.NEXT_PUBLIC_APP_URL ?? "https://app.sharedboost.com/mineme").replace(/\/$/, "");
  const referralUrl = profile?.referral_code && profile.referral_enabled
    ? `${siteUrl}/register?ref=${encodeURIComponent(profile.referral_code)}`
    : null;

  return (
    <main className="dashboard-shell">
      <header className="dashboard-topbar">
        <Link className="brand" href="/"><span className="brand-mark">M</span><span>MINE-ME</span></Link>
        <form action={signOutAction}><button className="signout-button" type="submit">Déconnexion</button></form>
      </header>
      <section className="dashboard-heading">
        <div className="eyebrow">ESPACE MEMBRE</div>
        <h1>Bonjour{profile?.display_name ? `, ${profile.display_name}` : ""}.</h1>
        <p>Voici votre espace personnel MINE-ME.</p>
      </section>
      {profile?.role === "admin" && <Link className="admin-shortcut" href="/admin">Ouvrir l’administration ↗</Link>}
      <AutoEnrollDevice />
      <section className="dashboard-grid">
        <article className="dashboard-card">
          <span className="card-label">APPAREILS ENREGISTRÉS</span>
          <strong className="metric">{devices?.length ?? 0}</strong>
          <p>Appareils rattachés à votre compte.</p>
        </article>
        <article className="dashboard-card">
          <span className="card-label">MINAGE</span>
          <strong className="metric metric-state">{platformAllowsMining ? "Autorisé" : "Désactivé"}</strong>
          <p>{platformAllowsMining
            ? "La plateforme autorise les connexions. Chaque appareil doit encore disposer d’une session valide et d’une connexion au pool."
            : "Le calcul reste désactivé par les paramètres de sécurité de la plateforme."}</p>
        </article>
        <article className="dashboard-card">
          <span className="card-label">INVITATIONS VALIDÉES</span>
          <strong className="metric">{referrals?.length ?? 0}</strong>
          <p>Comptes créés avec votre code de parrainage.</p>
        </article>
        <article className="dashboard-card">
          <span className="card-label">SHARES ACCEPTÉES VÉRIFIÉES</span>
          <strong className="metric">{acceptedShareCount}</strong>
          <p>Sur les 25 dernières shares vérifiées de vos appareils.</p>
        </article>
        <article className="dashboard-card referral-card">
          <span className="card-label">VOTRE PARRAINAGE</span>
          <strong className="referral-code">{profile?.referral_code ?? "En attente"}</strong>
          <p>Partagez ce lien uniquement avec les personnes que vous invitez.</p>
          {referralUrl && <><a className="text-link" href={referralUrl}>{referralUrl}</a><CopyReferralLink url={referralUrl} /></>}
        </article>
      </section>
      <section className="device-section">
        <div className="section-title"><div><span className="eyebrow">VOTRE FLOTTE</span><h2>Mes appareils</h2></div></div>
        {!devices?.length ? (
          <div className="empty-state"><strong>Aucun appareil enregistré</strong><p>L’association du navigateur apparaîtra ici après validation de votre consentement et de la configuration du compte.</p></div>
        ) : (
          <div className="device-list">{devices.map((device) => <DeviceControl key={device.id} device={device} maxIntensityPercent={maxIntensityPercent} />)}</div>
        )}
      </section>
      <section className="device-section">
        <div className="section-title"><div><span className="eyebrow">HISTORIQUE VÉRIFIÉ</span><h2>Activité de calcul</h2></div></div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Référence pool</th><th>Résultat</th><th>Difficulté</th><th>Vérification</th></tr></thead>
          <tbody>{verifiedShares.map((share) => <tr key={share.id}>
            <td><code>{share.pool_share_id}</code></td><td>{share.accepted ? "Acceptée" : "Rejetée"}</td>
            <td>{share.difficulty ?? "—"}</td>
            <td>{new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(share.verified_at))}</td>
          </tr>)}
          {!verifiedShares.length && <tr><td colSpan={4}>Aucune share vérifiée enregistrée.</td></tr>}</tbody>
        </table></div>
      </section>

      <section className="device-section">
        <div className="section-title"><div><span className="eyebrow">DIAGNOSTIC NAVIGATEUR</span><h2>Télémétrie de calcul</h2></div></div>
        <p className="dashboard-disclaimer">Taux de hachage déclaré par le navigateur uniquement. Il est indicatif, peut être falsifié et ne constitue ni une preuve de share acceptée ni un revenu.</p>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Worker</th><th>Hashrate navigateur</th><th>Hashes échantillonnés</th><th>Durée de l’échantillon</th><th>Dernière mesure</th></tr></thead>
          <tbody>{deviceTelemetry.map((sample) => <tr key={sample.device_id}>
            <td>{devices?.find((device) => device.id === sample.device_id)?.worker_code ?? "—"}</td>
            <td>{Number(sample.reported_hashrate).toFixed(2)} H/s</td>
            <td>{sample.hashes_computed}</td>
            <td>{Number(sample.sample_seconds).toFixed(1)} s</td>
            <td>{new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(sample.measured_at))}</td>
          </tr>)}
          {!deviceTelemetry.length && <tr><td colSpan={5}>Aucune télémétrie navigateur reçue.</td></tr>}</tbody>
        </table></div>
      </section>

      <section className="device-section">
        <div className="section-title"><div><span className="eyebrow">JOURNAL DES APPAREILS</span><h2>Historique des appareils</h2></div></div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Worker</th><th>Événement</th><th>Détails</th><th>Date</th></tr></thead>
          <tbody>{deviceEvents.map((event) => <tr key={event.id}>
            <td>{devices?.find((device) => device.id === event.device_id)?.worker_code ?? "—"}</td>
            <td>{event.event_type}</td><td>{event.details && Object.keys(event.details).length ? JSON.stringify(event.details) : "—"}</td>
            <td>{new Intl.DateTimeFormat("fr-FR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(event.created_at))}</td>
          </tr>)}
          {!deviceEvents.length && <tr><td colSpan={4}>Aucun événement enregistré pour vos appareils.</td></tr>}</tbody>
        </table></div>
      </section>
      <p className="dashboard-disclaimer">Les contributions éventuelles sont des données internes de suivi. Elles ne représentent pas un solde personnel et ne sont pas retirables.</p>
    </main>
  );
}
