import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "../dashboard/actions";
import AdminControls from "./admin-controls";
import AdminMemberControls from "./member-controls";
import AdminDeviceControls from "./device-controls";

function shortId(value: string | null | undefined) {
  return value ? value.slice(0, 8) : "—";
}

function formatDate(value: string | null | undefined) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("fr-FR", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

export default async function AdminPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/mineme/login");

  const { data: currentProfile } = await supabase
    .from("profiles")
    .select("role, display_name, account_status")
    .eq("id", user.id)
    .maybeSingle();

  if (currentProfile?.role !== "admin") redirect("/mineme/dashboard");
  if (currentProfile.account_status !== "active") redirect("/mineme/account-suspended");

  const [
    membersResult,
    devicesResult,
    referralsResult,
    sharesResult,
    receiptsResult,
    settingsResult,
    auditResult,
  ] = await Promise.all([
    supabase.from("profiles")
      .select("id, display_name, role, referral_code, referred_by, consent_version, consented_at, account_status, referral_enabled, created_at", { count: "exact" })
      .order("created_at", { ascending: false }).limit(100),
    supabase.from("devices")
      .select("id, user_id, worker_code, label, browser_family, platform_family, hardware_threads, intensity_percent, status, last_seen_at, created_at", { count: "exact" })
      .order("created_at", { ascending: false }).limit(100),
    supabase.from("referrals")
      .select("id, inviter_id, invitee_id, referral_code, created_at", { count: "exact" })
      .order("created_at", { ascending: false }).limit(100),
    supabase.from("mining_share_ledger")
      .select("id, device_id, pool_share_id, accepted, difficulty, verified_at", { count: "exact" })
      .order("verified_at", { ascending: false }).limit(100),
    supabase.from("central_wallet_receipts")
      .select("id, transaction_ref, asset, amount, network, confirmed_at, source", { count: "exact" })
      .order("confirmed_at", { ascending: false }).limit(50),
    supabase.from("platform_settings")
      .select("key, value")
      .in("key", ["mining_enabled", "global_emergency_pause", "global_max_intensity_percent"]),
    supabase.from("audit_logs")
      .select("id, actor_id, action, target_type, target_id, created_at", { count: "exact" })
      .order("created_at", { ascending: false }).limit(50),
  ]);

  const members = membersResult.data ?? [];
  const devices = devicesResult.data ?? [];
  const referrals = referralsResult.data ?? [];
  const shares = sharesResult.data ?? [];
  const receipts = receiptsResult.data ?? [];
  const audits = auditResult.data ?? [];
  const setting = (key: string) => settingsResult.data?.find((item) => item.key === key)?.value;
  const miningEnabledValue = setting("mining_enabled");
  const miningEnabled = miningEnabledValue === true;
  const emergencyPauseValue = setting("global_emergency_pause");
  const emergencyPause = emergencyPauseValue === undefined ? true : emergencyPauseValue === true;
  const maxIntensityValue = Number(setting("global_max_intensity_percent") ?? 80);
  const maxIntensity = Number.isFinite(maxIntensityValue) ? Math.min(80, Math.max(1, maxIntensityValue)) : 80;

  const userNames = new Map<string, string>(
    members.map((member) => [member.id, member.display_name || shortId(member.id)]),
  );
  const acceptedShares = shares.filter((share) => share.accepted).length;
  const rejectedShares = shares.filter((share) => !share.accepted).length;

  return (
    <main className="dashboard-shell">
      <header className="dashboard-topbar">
        <Link className="brand" href="/"><span className="brand-mark">M</span><span>MINE-ME / ADMIN</span></Link>
        <form action={signOutAction}><button className="signout-button" type="submit">Déconnexion</button></form>
      </header>

      <section className="dashboard-heading">
        <div className="eyebrow">CONSOLE DE CONTRÔLE</div>
        <h1>Administration.</h1>
        <p>Connecté en tant que {currentProfile.display_name || user.email || "administrateur"}.</p>
      </section>

      <div className="admin-warning">
        <strong>Minage réel désactivé</strong>
        <p>Le moteur WASM, le passerelle WSS et la vérification des shares ne sont pas encore déployés. Cette console n’affiche que les données réellement enregistrées dans la base. Aucun chiffre de production n’est simulé.</p>
      </div>

      <section className="dashboard-grid admin-metrics">
        <article className="dashboard-card"><span className="card-label">COMPTES</span><strong className="metric">{membersResult.count ?? members.length}</strong><p>Comptes membres enregistrés.</p></article>
        <article className="dashboard-card"><span className="card-label">APPAREILS</span><strong className="metric">{devicesResult.count ?? devices.length}</strong><p>Navigateurs/appareils associés.</p></article>
        <article className="dashboard-card"><span className="card-label">PARRAINAGES</span><strong className="metric">{referralsResult.count ?? referrals.length}</strong><p>Inscriptions attribuées à un code.</p></article>
        <article className="dashboard-card"><span className="card-label">SHARES ACCEPTÉES VÉRIFIÉES</span><strong className="metric">{acceptedShares}</strong><p>{rejectedShares} rejetée(s) parmi les {shares.length} dernières entrées vérifiées.</p></article>
        <article className="dashboard-card"><span className="card-label">REÇUS DU PORTEFEUILLE CENTRAL</span><strong className="metric">{receiptsResult.count ?? receipts.length}</strong><p>Reçus confirmés enregistrés.</p></article>
        <article className="dashboard-card"><span className="card-label">JOURNAL D’AUDIT</span><strong className="metric">{auditResult.count ?? audits.length}</strong><p>Actions administratives historisées.</p></article>
      </section>

      <AdminControls initialMiningEnabled={miningEnabled} initialEmergencyPause={emergencyPause} initialMaxIntensity={maxIntensity} />

      <section className="admin-section">
        <div className="admin-section-heading"><span className="eyebrow">01 / MEMBRES</span><h2>Comptes utilisateurs</h2></div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Membre</th><th>Rôle</th><th>Code de parrainage</th><th>Parrain</th><th>Consentement</th><th>État</th><th>Code actif</th><th>Inscription</th><th>Actions</th></tr></thead>
          <tbody>{members.map((member) => <tr key={member.id}>
            <td><strong>{member.display_name || "Sans nom"}</strong><small>{shortId(member.id)}</small></td>
            <td>{member.role}</td><td><code>{member.referral_code}</code></td>
            <td>{member.referred_by ? userNames.get(member.referred_by) || shortId(member.referred_by) : "Premier administrateur"}</td>
            <td>{member.consent_version || "—"}</td>
            <td>{member.account_status}</td><td>{member.referral_enabled ? "Oui" : "Non"}</td>
            <td>{formatDate(member.created_at)}</td>
            <td><AdminMemberControls memberId={member.id} accountStatus={member.account_status} referralEnabled={member.referral_enabled} /></td>
          </tr>)}
          {!members.length && <tr><td colSpan={9}>Aucun compte enregistré.</td></tr>}</tbody>
        </table></div>
      </section>

      <section className="admin-section">
        <div className="admin-section-heading"><span className="eyebrow">02 / APPAREILS</span><h2>Flotte des navigateurs</h2></div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Worker</th><th>Membre</th><th>Plateforme / navigateur</th><th>Cœurs logiques déclarés</th><th>Intensité souhaitée</th><th>État</th><th>Dernier contact</th><th>Actions</th></tr></thead>
          <tbody>{devices.map((device) => <tr key={device.id}>
            <td><code>{device.worker_code}</code></td>
            <td>{userNames.get(device.user_id) || shortId(device.user_id)}</td>
            <td>{device.platform_family || "—"} / {device.browser_family || "—"}</td>
            <td>{device.hardware_threads ?? "—"}</td><td>{device.intensity_percent}%</td><td>{device.status}</td>
            <td>{formatDate(device.last_seen_at)}</td><td><AdminDeviceControls deviceId={device.id} status={device.status} /></td>
          </tr>)}
          {!devices.length && <tr><td colSpan={8}>Aucun appareil associé.</td></tr>}</tbody>
        </table></div>
      </section>

      <section className="admin-section">
        <div className="admin-section-heading"><span className="eyebrow">03 / PARRAINAGES</span><h2>Attribution des inscriptions</h2></div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Code utilisé</th><th>Parrain</th><th>Nouveau membre</th><th>Date</th></tr></thead>
          <tbody>{referrals.map((referral) => <tr key={referral.id}>
            <td><code>{referral.referral_code}</code></td><td>{userNames.get(referral.inviter_id) || shortId(referral.inviter_id)}</td>
            <td>{userNames.get(referral.invitee_id) || shortId(referral.invitee_id)}</td><td>{formatDate(referral.created_at)}</td>
          </tr>)}
          {!referrals.length && <tr><td colSpan={4}>Aucun parrainage enregistré.</td></tr>}</tbody>
        </table></div>
      </section>

      <section className="admin-section">
        <div className="admin-section-heading"><span className="eyebrow">04 / POOL &amp; COMPTABILITÉ</span><h2>Shares et portefeuille central</h2></div>
        <div className="pool-status-card"><span className="pool-indicator" /> Passerelle pool : non configurée — aucun travail de minage n’est envoyé.</div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Référence share pool</th><th>Worker</th><th>Acceptée</th><th>Difficulté</th><th>Vérifiée le</th></tr></thead>
          <tbody>{shares.map((share) => <tr key={share.id}>
            <td><code>{share.pool_share_id}</code></td><td>{shortId(share.device_id)}</td><td>{share.accepted ? "Oui" : "Non"}</td>
            <td>{share.difficulty ?? "—"}</td><td>{formatDate(share.verified_at)}</td>
          </tr>)}
          {!shares.length && <tr><td colSpan={5}>Aucune share vérifiée par un pool.</td></tr>}</tbody>
        </table></div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Transaction</th><th>Actif</th><th>Montant</th><th>Réseau</th><th>Source</th><th>Confirmée le</th></tr></thead>
          <tbody>{receipts.map((receipt) => <tr key={receipt.id}>
            <td><code>{receipt.transaction_ref}</code></td><td>{receipt.asset}</td><td>{receipt.amount}</td>
            <td>{receipt.network}</td><td>{receipt.source}</td><td>{formatDate(receipt.confirmed_at)}</td>
          </tr>)}
          {!receipts.length && <tr><td colSpan={6}>Aucun reçu de paiement central enregistré.</td></tr>}</tbody>
        </table></div>
      </section>

      <section className="admin-section">
        <div className="admin-section-heading"><span className="eyebrow">05 / TRAÇABILITÉ</span><h2>Journal d’audit</h2></div>
        <div className="admin-table-wrap"><table className="admin-table">
          <thead><tr><th>Action</th><th>Acteur</th><th>Cible</th><th>Date</th></tr></thead>
          <tbody>{audits.map((log) => <tr key={log.id}>
            <td>{log.action}</td><td>{userNames.get(log.actor_id || "") || shortId(log.actor_id)}</td>
            <td>{log.target_type || "—"} {shortId(log.target_id)}</td><td>{formatDate(log.created_at)}</td>
          </tr>)}
          {!audits.length && <tr><td colSpan={4}>Aucune action administrative enregistrée.</td></tr>}</tbody>
        </table></div>
      </section>
      <p className="dashboard-disclaimer">Les commandes de contrôle et paramètres ne peuvent pas démarrer le minage ni annuler le consentement d’un participant. Les recettes affichées doivent provenir de reçus de portefeuille vérifiés.</p>
    </main>
  );
}
