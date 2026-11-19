"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";

type Device = {
  id: string;
  worker_code: string;
  label: string | null;
  status: string;
  intensity_percent: number;
  last_seen_at: string | null;
};

export default function DeviceControl({ device }: { device: Device }) {
  const [intensity, setIntensity] = useState(device.intensity_percent);
  const [savedIntensity, setSavedIntensity] = useState(device.intensity_percent);
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState("");
  const router = useRouter();

  async function saveIntensity() {
    setBusy(true);
    setFeedback("");
    try {
      const supabase = createClient();
      const { data: { user }, error: authError } = await supabase.auth.getUser();
      if (authError || !user) throw new Error("Session membre introuvable.");

      const { error } = await supabase
        .from("devices")
        .update({ intensity_percent: intensity })
        .eq("id", device.id)
        .eq("user_id", user.id);

      if (error) throw error;
      setSavedIntensity(intensity);
      setFeedback("Préférence enregistrée. Elle sera appliquée lorsque le moteur de calcul sera activé.");
    } catch {
      setFeedback("Impossible d’enregistrer cette préférence. Réessayez.");
    } finally {
      setBusy(false);
    }
  }

  async function changeParticipation(nextStatus: "paused" | "stopped") {
    setBusy(true);
    setFeedback("");
    try {
      const supabase = createClient();
      const { data: { user }, error: authError } = await supabase.auth.getUser();
      if (authError || !user) throw new Error("Session membre introuvable.");

      const { error } = await supabase
        .from("devices")
        .update({ status: nextStatus })
        .eq("id", device.id)
        .eq("user_id", user.id);

      if (error) throw error;
      setFeedback(nextStatus === "paused" ? "Appareil mis en pause." : "Participation arrêtée sur cet appareil.");
      router.refresh();
    } catch {
      setFeedback("Impossible de modifier l’état de cet appareil. Réessayez.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <article className="device-row device-card">
      <div className="device-main">
        <div className="device-title"><strong>{device.label || device.worker_code}</strong><span className="device-status">{device.status === "enrolled" ? "Associé" : device.status}</span></div>
        <small>{device.worker_code}</small>
        <div className="intensity-editor">
          <div className="intensity-label"><label htmlFor={`intensity-${device.id}`}>Intensité souhaitée</label><strong>{intensity}%</strong></div>
          <input id={`intensity-${device.id}`} type="range" min="1" max="80" step="1" value={intensity} onChange={(e) => setIntensity(Number(e.target.value))} />
          <div className="intensity-scale"><span>Économie</span><span>Puissance</span></div>
          <button className="save-intensity" type="button" onClick={saveIntensity} disabled={busy || intensity === savedIntensity}>{busy ? "Enregistrement…" : "Enregistrer la préférence"}</button>
          <div className="device-actions">
            <button className="mini-action" type="button" disabled={busy || device.status === "paused" || device.status === "stopped" || device.status === "blocked"} onClick={() => changeParticipation("paused")}>Mettre en pause</button>
            <button className="mini-action danger-action" type="button" disabled={busy || device.status === "stopped" || device.status === "blocked"} onClick={() => changeParticipation("stopped")}>Arrêter cet appareil</button>
          </div>
          {feedback && <p className="device-feedback" role="status">{feedback}</p>}
        </div>
      </div>
    </article>
  );
}
