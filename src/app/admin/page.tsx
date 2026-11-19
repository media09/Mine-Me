import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "../dashboard/actions";

export default async function AdminPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/mineme/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("role, display_name")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.role !== "admin") redirect("/mineme/dashboard");

  return (
    <main className="dashboard-shell">
      <header className="dashboard-topbar">
        <Link className="brand" href="/"><span className="brand-mark">M</span><span>MINE-ME / ADMIN</span></Link>
        <form action={signOutAction}><button className="signout-button" type="submit">Déconnexion</button></form>
      </header>
      <section className="dashboard-heading">
        <div className="eyebrow">CONSOLE DE CONTRÔLE</div>
        <h1>Administration.</h1>
        <p>Accès réservé aux comptes dont le rôle administrateur est vérifié côté serveur.</p>
      </section>
      <div className="admin-warning"><strong>Minage désactivé</strong><p>Aucune commande de minage ni aucun contrôle global n’est encore disponible. Ces fonctions seront ajoutées après la mise en place du passerelle WSS, des contrôles d’accès et de la vérification du pool.</p></div>
      <section className="dashboard-grid admin-grid">
        <article className="dashboard-card"><span className="card-label">UTILISATEURS</span><strong className="metric">—</strong><p>Les statistiques seront branchées sur des requêtes serveur sécurisées.</p></article>
        <article className="dashboard-card"><span className="card-label">APPAREILS</span><strong className="metric">—</strong><p>Aucun statut de minage fictif n’est affiché.</p></article>
        <article className="dashboard-card"><span className="card-label">PAIEMENTS POOL</span><strong className="metric">—</strong><p>Seuls les paiements vérifiés seront comptabilisés.</p></article>
      </section>
    </main>
  );
}
