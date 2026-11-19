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

  async function update(column: "account_status" | "referral_enabled", value: string | boolean) {
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

      const { error } = await supabase
        .from("profiles")
        .update({ [column]: value })
        .eq("id", memberId);
      if (error) {
        if (error.message.includes("last active administrator")) {
          throw new Error("Le dernier administrateur actif ne peut pas être suspendu.");
        }
        throw error;
      }

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
      <button type="button" disabled={busy} className="mini-action" onClick={() => update("account_status", accountStatus === "active" ? "suspended" : "active")}>
        {accountStatus === "active" ? "Suspendre" : "Réactiver"}
      </button>
      <button type="button" disabled={busy || (accountStatus !== "active" && !referralEnabled)} className="mini-action" onClick={() => update("referral_enabled", !referralEnabled)}>
        {referralEnabled ? "Désactiver code" : "Activer code"}
      </button>
      {feedback && <span className="action-feedback" role="status">{feedback}</span>}
    </div>
  );
}
