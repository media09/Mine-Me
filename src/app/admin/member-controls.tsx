"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function AdminMemberControls({
  memberId,
  accountStatus,
  referralEnabled,
}: {
  memberId: string;
  accountStatus: "active" | "suspended";
  referralEnabled: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState("");

  async function call(functionName: "admin_set_member_status" | "admin_set_referral_enabled", args: Record<string, unknown>) {
    setBusy(true);
    setFeedback("");
    try {
      const supabase = createClient();
      const { error } = await supabase.rpc(functionName, args);
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
      <button type="button" disabled={busy} className="mini-action" onClick={() => call("admin_set_member_status", { p_member_id: memberId, p_status: accountStatus === "active" ? "suspended" : "active" })}>
        {accountStatus === "active" ? "Suspendre" : "Réactiver"}
      </button>
      <button type="button" disabled={busy || accountStatus !== "active"} className="mini-action" onClick={() => call("admin_set_referral_enabled", { p_member_id: memberId, p_enabled: !referralEnabled })}>
        {referralEnabled ? "Désactiver code" : "Activer code"}
      </button>
      {feedback && <span className="action-feedback" role="status">{feedback}</span>}
    </div>
  );
}
