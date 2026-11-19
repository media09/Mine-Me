"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function AdminControls({
  initialEmergencyPause,
  initialMaxIntensity,
}: {
  initialEmergencyPause: boolean;
  initialMaxIntensity: number;
}) {
  const router = useRouter();
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
        .select("role")
        .eq("id", user.id)
        .single();

      if (profileError || profile?.role !== "admin") {
        throw new Error("Accès administrateur refusé.");
      }

      const [pauseWrite, limitWrite] = await Promise.all([
        supabase.from("platform_settings")
          .update({ value: emergencyPause, updated_at: new Date().toISOString() })
          .eq("key", "global_emergency_pause")
          .select("key")
          .single(),
        supabase.from("platform_settings")
          .update({ value: maxIntensity, updated_at: new Date().toISOString() })
          .eq("key", "global_max_intensity_percent")
          .select("key")
          .single(),
      ]);

      if (pauseWrite.error || limitWrite.error) {
        throw new Error("Les paramètres n’ont pas pu être enregistrés.");
      }

      setFeedback("Paramètres enregistrés. Ils ne contrôlent pas encore un moteur actif : le minage reste désactivé tant que le service de minage n’a pas été validé.");
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
        <span className="admin-config-state">Configuration enregistrable</span>
      </div>
      <div className="admin-setting-row">
        <div><strong>Pause d’urgence globale</strong><p>Le futur moteur devra refuser tout nouveau travail lorsque cette pause est activée.</p></div>
        <button
          className={emergencyPause ? "toggle-button is-on" : "toggle-button"}
          type="button"
          aria-pressed={emergencyPause}
          onClick={() => setEmergencyPause((value) => !value)}
        >{emergencyPause ? "Activée" : "Désactivée"}</button>
      </div>
      <div className="admin-setting-row">
        <div><strong>Intensité maximale autorisée</strong><p>Plafond que le moteur devra appliquer en plus du choix individuel du participant.</p></div>
        <strong className="admin-limit-value">{maxIntensity}%</strong>
      </div>
      <input className="admin-range" aria-label="Intensité maximale" type="range" min="1" max="80" value={maxIntensity} onChange={(event) => setMaxIntensity(Number(event.target.value))} />
      <div className="intensity-scale"><span>1% — prudent</span><span>80% — plafond</span></div>
      <button className="save-intensity" type="button" disabled={busy} onClick={save}>{busy ? "Enregistrement…" : "Enregistrer les paramètres"}</button>
      {feedback && <p className="device-feedback" role="status">{feedback}</p>}
      <p className="admin-note">Ces paramètres seront appliqués par le passerelle de calcul lorsqu’il sera développé. Ils ne démarrent pas le minage et ne peuvent pas annuler le consentement d’un participant.</p>
    </section>
  );
}
