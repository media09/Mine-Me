import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "./actions";
import CopyReferralLink from "./copy-referral-link";

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/mineme/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name, referral_code, role, consented_at")
    .eq("id", user.id)
    .maybeSingle();

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

  const siteUrl = (process.env.NEXT_PUBLIC_APP_URL ?? "https://app.sharedboost.com/mineme").replace(/\/$/, "");
  const referralUrl = profile?.referral_code
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
      <section className="dashboard-grid">
        <article className="dashboard-card">
          <span className="card-label">APPAREILS ENREGISTRÉS</span>
          <strong className="metric">{devices?.length ?? 0}</strong>
          <p>Appareils rattachés à votre compte.</p>
        </article>
        <article className="dashboard-card">
          <span className="card-label">MINAGE</span>
          <strong className="metric metric-state">Non activé</strong>
          <p>Le module de minage réel sera activé uniquement après validation technique du pool.</p>
        </article>
        <article className="dashboard-card">
          <span className="card-label">INVITATIONS VALIDÉES</span>
          <strong className="metric">{referrals?.length ?? 0}</strong>
          <p>Comptes créés avec votre code de parrainage.</p>
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
          <div className="empty-state"><strong>Aucun appareil enregistré</strong><p>Votre navigateur pourra être enregistré après activation du module de calcul et avec votre consentement.</p></div>
        ) : (
          <div className="device-list">{devices.map((device) => <article className="device-row" key={device.id}><div><strong>{device.label || device.worker_code}</strong><small>{device.worker_code}</small></div><span className="device-status">{device.status}</span><span>{device.intensity_percent}%</span></article>)}</div>
        )}
      </section>
      <p className="dashboard-disclaimer">Les contributions éventuelles sont des données internes de suivi. Elles ne représentent pas un solde personnel et ne sont pas retirables.</p>
    </main>
  );
}
