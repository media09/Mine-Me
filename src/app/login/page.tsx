"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      const supabase = createClient();
      const { error: loginError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (loginError) {
        setError("Connexion impossible. Vérifiez votre adresse e-mail et votre mot de passe.");
        return;
      }
      window.location.assign("/mineme/dashboard");
    } catch {
      setError("Le service est momentanément indisponible. Réessayez.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="auth-shell">
      <Link className="auth-brand" href="/">◇ MINE-ME</Link>
      <section className="auth-card">
        <div className="auth-kicker">ESPACE MEMBRE</div>
        <h1>Content de vous revoir.</h1>
        <p className="auth-intro">Connectez-vous à votre espace MINE-ME.</p>
        <form className="auth-form" onSubmit={handleSubmit}>
          <label>Adresse e-mail<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" required /></label>
          <label>Mot de passe<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required /></label>
          {error && <p className="form-error" role="alert">{error}</p>}
          <button className="auth-submit" type="submit" disabled={busy}>{busy ? "Connexion…" : "Se connecter"}</button>
        </form>
        <p className="auth-switch">Pas encore membre ? <Link href="/register">Utiliser une invitation</Link></p>
      </section>
    </main>
  );
}
