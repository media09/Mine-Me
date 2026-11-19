import Link from "next/link";

export default function AccountSuspendedPage() {
  return (
    <main className="auth-shell">
      <Link className="auth-brand" href="/">◇ MINE-ME</Link>
      <section className="auth-card">
        <div className="auth-kicker">ACCÈS SUSPENDU</div>
        <h1>Votre compte est temporairement suspendu.</h1>
        <p className="auth-intro">L’accès aux fonctions de participation et à vos appareils a été suspendu par l’administration. Contactez l’équipe MINE-ME pour plus d’informations.</p>
        <Link className="primary-link" href="/login">Retour à la connexion</Link>
      </section>
    </main>
  );
}
