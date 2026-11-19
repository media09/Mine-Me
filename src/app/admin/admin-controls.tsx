"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function AdminControls({
  initialMiningEnabled,
  initialEmergencyPause,
  initialMaxIntensity,
}: {
  initialMiningEnabled: boolean;
  initialEmergencyPause: boolean;
  initialMaxIntensity: number;
}) {
  const router = useRouter();
  const [miningEnabled, setMiningEnabled] = useState(initialMiningEnabled);
  const [emergencyPause, setEmergencyPause] = useState(initialEmergencyPause);
  const [maxIntensity, setMaxIntensity] = useState(initialMaxIntensity);
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState("");

  async function save() {
    setBusy(true);
    setFeedback("");
    try {
      const supabase = createClient();
      const { data: { user }, error: authError } = await supabase.auth.getUser();
      if (authError || !user) throw new Error("Session administrateur introuvable.");

      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("role, account_status")
        .eq("id", user.id)
        .single();

      if (profileError || profile?.role !== "admin" || profile.account_status !== "active") {
        throw new Error("Accès administrateur refusé.");
      }

      const now = new Date().toISOString();
      const [miningWrite, pauseWrite, limitWrite] = await Promise.all([
        supabase.from("platform_settings")
          .update({ value: miningEnabled, updated_at: now })
          .eq("key", "mining_enabled")
          .select("key")
          .single(),
        supabase.from("platform_settings")
          .update({ value: emergencyPause, updated_at: now })
          .eq("key", "global_emergency_pause")
          .select("key")
          .single(),
        supabase.from("platform_settings")
          .update({ value: maxIntensity, updated_at: now })
          .eq("key", "global_max_intensity_percent")
          .select("key")
          .single(),
      ]);

      if (miningWrite.error || pauseWrite.error || limitWrite.error) {
        throw new Error("Les paramètres n’ont pas pu être enregistrés.");
      }

      setFeedback(
        miningEnabled && !emergencyPause
          ? "Paramètres enregistrés. Le service de minage doit encore être configuré et validé avant toute activation effective."
          : "Paramètres enregistrés. Les appareils en cours ont été mis en pause lorsque la sécurité l’exige.",
      );
      router.refresh();
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : "Une erreur est survenue.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="admin-controls">
      <div className="admin-controls-head">
        <div><span className="card-label">SÉCURITÉ DE LA FLOTTE</span><h2>Limites globales</h2></div>
        <span className="admin-config-state">Configuration administrateur</span>
      </div>
      <div className="admin-setting-row">
        <div><strong>Autoriser le minage</strong><p>Interrupteur général. Il doit rester désactivé tant que la passerelle WSS et le pool ne sont pas configurés et testés.</p></div>
        <button
          className={miningEnabled ? "toggle-button" : "toggle-button is-on"}
          type="button"
          aria-pressed={miningEnabled}
          onClick={() => setMiningEnabled((value) => !value)}
        >{miningEnabled ? "Autorisé" : "Désactivé"}</button>
      </div>
      <div className="admin-setting-row">
        <div><strong>Pause d’urgence globale</strong><p>Lorsqu’elle est activée, les appareils en cours sont mis en pause par la base de données.</p></div>
        <button
          className={emergencyPause ? "toggle-button is-on" : "toggle-button"}
          type="button"
          aria-pressed={emergencyPause}
          onClick={() => setEmergencyPause((value) => !value)}
        >{emergencyPause ? "Activée" : "Désactivée"}</button>
      </div>
      <div className="admin-setting-row">
        <div><strong>Intensité maximale autorisée</strong><p>Plafond serveur appliqué en plus du choix individuel du participant.</p></div>
        <strong className="admin-limit-value">{maxIntensity}%</strong>
      </div>
      <input className="admin-range" aria-label="Intensité maximale" type="range" min="1" max="80" value={maxIntensity} onChange={(event) => setMaxIntensity(Number(event.target.value))} />
      <div className="intensity-scale"><span>1% — prudent</span><span>80% — plafond</span></div>
      <button className="save-intensity" type="button" disabled={busy} onClick={save}>{busy ? "Enregistrement…" : "Enregistrer les paramètres"}</button>
      {feedback && <p className="device-feedback" role="status">{feedback}</p>}
      <p className="admin-note">L’activation globale ne peut pas démarrer le minage à elle seule. La participation dépend aussi du consentement, de l’état du compte, de l’appareil et du service pool vérifié. Les administrateurs ne peuvent pas outrepasser le consentement individuel.</p>
    </section>
  );
}
