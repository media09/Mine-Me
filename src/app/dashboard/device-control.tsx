"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

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
          {feedback && <p className="device-feedback" role="status">{feedback}</p>}
        </div>
      </div>
    </article>
  );
}
