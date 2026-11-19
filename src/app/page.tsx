const principles = [
  {
    number: "01",
    title: "Consentement explicite",
    description:
      "Aucun calcul ne démarre en secret. La participation et ses conditions sont expliquées avant toute activation.",
  },
  {
    number: "02",
    title: "Votre appareil, vos limites",
    description:
      "Vous choisissez l’intensité. Vous pouvez réduire la charge, mettre en pause ou arrêter à tout moment.",
  },
  {
    number: "03",
    title: "Comptabilité vérifiable",
    description:
      "Les shares acceptées par le pool et les paiements confirmés font foi. Aucun gain fictif ou estimé n’est présenté comme réel.",
  },
];

export default function Home() {
  return (
    <main className="site-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="MINE-ME, accueil">
          <span className="brand-mark">M</span>
          <span>MINE-ME</span>
        </a>
        <a className="top-link" href="#principes">Notre fonctionnement <span>↗</span></a>
      </header>

      <section className="hero" id="top">
        <div className="eyebrow"><span className="live-dot" /> RÉSEAU DE CALCUL COMMUNAUTAIRE</div>
        <h1>La puissance de calcul,<br /><span>mise en commun.</span></h1>
        <p className="hero-copy">
          MINE-ME rassemble volontairement des capacités de calcul via le navigateur.
          Vous gardez le contrôle de votre appareil, de son intensité et de votre participation.
        </p>
        <a className="primary-link" href="#principes">Découvrir le projet <span>↗</span></a>

        <div className="system-card" aria-label="État actuel de la plateforme">
          <div className="card-heading">
            <span>ÉTAT DE LA PLATEFORME</span>
            <span className="status-pill"><i /> Fondation en préparation</span>
          </div>
          <div className="status-grid">
            <div><small>PARTICIPATION</small><strong>Consentement requis</strong></div>
            <div><small>ENVIRONNEMENT</small><strong>Navigateur web</strong></div>
            <div><small>CONTRÔLE</small><strong>Participant</strong></div>
          </div>
          <p className="card-note">
            Le minage réel n’est pas encore activé. Les données de production ne seront affichées
            qu’après intégration et vérification des données du pool.
          </p>
        </div>
      </section>

      <section className="principles" id="principes">
        <div className="section-kicker">01 / NOS ENGAGEMENTS</div>
        <h2>Conçu pour être clair.<br />Pensé pour être contrôlé.</h2>
        <div className="principle-grid">
          {principles.map((item) => (
            <article className="principle-card" key={item.number}>
              <span className="principle-number">{item.number}</span>
              <h3>{item.title}</h3>
              <p>{item.description}</p>
            </article>
          ))}
        </div>
      </section>

      <footer className="footer">
        <a className="brand" href="#top"><span className="brand-mark">M</span><span>MINE-ME</span></a>
        <p>Participation volontaire. Aucun rendement garanti.</p>
      </footer>
    </main>
  );
}
