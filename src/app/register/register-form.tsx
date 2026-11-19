"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

const CONSENT_VERSION = "2026-11-19-v1";

export default function RegisterForm({
  initialReferralCode,
}: {
  initialReferralCode: string;
}) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [referralCode, setReferralCode] = useState(initialReferralCode.toUpperCase());
  const [consent, setConsent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setMessage("");

    if (!consent) {
      setError("Vous devez lire et accepter les conditions de participation pour continuer.");
      return;
    }
    if (!referralCode.trim()) {
      setError("Un code d’invitation valide est obligatoire.");
      return;
    }

    setBusy(true);
    try {
      const supabase = createClient();
      const { data, error: signUpError } = await supabase.auth.signUp({
        email: email.trim(),
        password,
        options: {
          data: {
            display_name: name.trim(),
            referral_code: referralCode.trim().toUpperCase(),
            consent_to_compute: true,
            consent_version: CONSENT_VERSION,
          },
        },
      });

      if (signUpError) {
        const message = signUpError.message.toLowerCase();
        if (message.includes("referral") || message.includes("invitation")) {
          setError("Ce code d’invitation est invalide, expiré ou déjà utilisé. Vérifiez le lien reçu.");
        } else if (message.includes("consent") || message.includes("acceptance")) {
          setError("L’acceptation des conditions de participation est nécessaire pour créer un compte.");
        } else if (message.includes("already registered")) {
          setError("Un compte existe déjà avec cette adresse e-mail. Connectez-vous plutôt.");
        } else {
          setError("Impossible de créer votre compte pour le moment. Vérifiez vos informations et réessayez.");
        }
        return;
      }

      if (data.session) {
        window.location.assign("/mineme/dashboard");
      } else {
        setMessage("Votre demande a été enregistrée. Consultez votre boîte e-mail pour confirmer votre adresse. Le minage n’est pas encore activé sur cette version.");
      }
    } catch {
      setError("Une erreur inattendue est survenue. Réessayez dans quelques instants.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="auth-shell">
      <Link className="auth-brand" href="/">◇ MINE-ME</Link>
      <section className="auth-card">
        <div className="auth-kicker">ACCÈS SUR INVITATION</div>
        <h1>Rejoindre MINE-ME</h1>
        <p className="auth-intro">Créez votre compte avec un code d’invitation valide.</p>
        <form className="auth-form" onSubmit={handleSubmit}>
          <label>Nom affiché<input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" required maxLength={80} /></label>
          <label>Adresse e-mail<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" required /></label>
          <label>Mot de passe<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" minLength={8} required /></label>
          <label>Code d’invitation<input value={referralCode} onChange={(e) => setReferralCode(e.target.value.toUpperCase())} autoCapitalize="characters" required /></label>

          <div className="consent-box">
            <label className="consent-check">
              <input type="checkbox" checked={consent} onChange={(e) => setConsent(e.target.checked)} />
              <span>J’ai lu et j’accepte les conditions de participation.</span>
            </label>
            <p>
              Je comprends que MINE-ME pourra utiliser une partie des ressources de calcul
              de mon appareil dans mon navigateur lorsque la fonction sera activée. Je choisirai
              l’intensité et pourrai mettre en pause ou arrêter à tout moment. Cette activité peut
              augmenter la consommation électrique et de données, la chaleur, le bruit des ventilateurs
              et l’usure de l’appareil ou de sa batterie. Le navigateur peut suspendre les onglets en arrière-plan.
            </p>
            <p className="ownership-notice">
              Tous les produits du minage appartiennent à la plateforme MINE-ME. Les participants
              ne reçoivent aucun partage de revenus ni solde individuel retirable. Les statistiques
              par appareil sont uniquement des données internes d’attribution.
            </p>
            <Link href="/terms" className="terms-link">Lire les conditions complètes</Link>
          </div>

          {error && <p className="form-error" role="alert">{error}</p>}
          {message && <p className="form-success" role="status">{message}</p>}
          <button className="auth-submit" type="submit" disabled={busy}>{busy ? "Création en cours…" : "Créer mon compte"}</button>
        </form>
        <p className="auth-switch">Vous avez déjà un compte ? <Link href="/login">Se connecter</Link></p>
      </section>
      <p className="auth-footnote">Aucun minage caché. Aucune promesse de rendement.</p>
    </main>
  );
}
