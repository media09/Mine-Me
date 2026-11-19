"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function AdminDeviceControls({
  deviceId,
  status,
}: {
  deviceId: string;
  status: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState("");

  async function setStatus(nextStatus: "enrolled" | "paused" | "blocked") {
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

      const { error } = await supabase.from("devices")
        .update({ status: nextStatus })
        .eq("id", deviceId);
      if (error) throw error;

      setFeedback("Mis à jour");
      router.refresh();
    } catch (error) {
      setFeedback(error instanceof Error ? error.message : "Action impossible");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="admin-row-actions">
      {status !== "blocked" && <button type="button" className="mini-action danger-action" disabled={busy} onClick={() => setStatus("blocked")}>Bloquer</button>}
      {status !== "paused" && status !== "blocked" && <button type="button" className="mini-action" disabled={busy} onClick={() => setStatus("paused")}>Mettre en pause</button>}
      {(status === "paused" || status === "blocked" || status === "stopped" || status === "offline") &&
        <button type="button" className="mini-action" disabled={busy} onClick={() => setStatus("enrolled")}>Réautoriser</button>}
      {feedback && <span className="action-feedback" role="status">{feedback}</span>}
    </div>
  );
}
