import Link from "next/link";

export default function TermsPage() {
  return (
    <main className="terms-shell">
      <Link className="auth-brand" href="/">◇ MINE-ME</Link>
      <article className="terms-card">
        <div className="auth-kicker">VERSION 2026-11-19-V1</div>
        <h1>Conditions de participation</h1>
        <h2>Participation volontaire</h2>
        <p>Votre appareil ne doit effectuer aucun calcul pour MINE-ME sans votre accord explicite. Vous choisissez de rejoindre le programme et pouvez arrêter votre participation à tout moment.</p>
        <h2>Utilisation des ressources</h2>
        <p>Lorsque le module sera activé, une partie des ressources de calcul de votre appareil pourra être utilisée dans le navigateur. Cela peut augmenter l’utilisation du processeur, la consommation d’énergie et de données, la chaleur, le bruit des ventilateurs ainsi que l’usure de l’appareil ou de sa batterie. Le navigateur et le système d’exploitation peuvent limiter ou suspendre les onglets en arrière-plan.</p>
        <h2>Intensité et arrêt</h2>
        <p>Vous contrôlez l’intensité de calcul et pouvez mettre en pause ou arrêter à tout moment. Les limites de sécurité de la plateforme peuvent réduire la charge maximale autorisée, mais ne peuvent pas forcer votre appareil à participer.</p>
        <h2>Propriété des produits du minage</h2>
        <p>Tous les produits du minage appartiennent à la plateforme MINE-ME. Les participants ne reçoivent aucun partage de revenus, aucune rémunération liée à leurs shares et aucun solde individuel retirable. Les données attribuées à un appareil sont des statistiques internes d’exploitation uniquement.</p>
        <h2>Mesures vérifiables</h2>
        <p>Les données présentées comme shares acceptées doivent provenir du pool ou d'une source de vérification serveur. Les estimations du navigateur ne constituent pas une preuve de revenu. Aucune rentabilité n’est garantie.</p>
        <p className="terms-version">Ce texte est la base de consentement produit. Une validation juridique locale est requise avant lancement public.</p>
      </article>
    </main>
  );
}
