import { NextResponse } from "next/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const DECIMAL_PATTERN = /^(?:0|[1-9]\d{0,17})(?:\.\d{1,12})?$/;
const ATOMIC_UNITS = 1_000_000_000_000n;

function parseAtomic(value: unknown): bigint | null {
  if (typeof value !== "string" || !DECIMAL_PATTERN.test(value)) return null;
  const [whole, fraction = ""] = value.split(".");
  return BigInt(whole) * ATOMIC_UNITS + BigInt((fraction + "000000000000").slice(0, 12));
}

function formatAtomic(value: bigint): string {
  const whole = value / ATOMIC_UNITS;
  const fraction = (value % ATOMIC_UNITS).toString().padStart(12, "0");
  return `${whole}.${fraction}`;
}

function parseTimestamp(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) {
    return NextResponse.json({ error: "Origine de requête non autorisée." }, { status: 403 });
  }

  const userClient = await createClient();
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return NextResponse.json({ error: "Authentification requise." }, { status: 401 });
  }

  const { data: profile, error: profileError } = await userClient
    .from("profiles")
    .select("role, account_status")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError || profile?.role !== "admin" || profile.account_status !== "active") {
    return NextResponse.json({ error: "Accès administrateur requis." }, { status: 403 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json() as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "Corps JSON invalide." }, { status: 400 });
  }

  const transactionRef = typeof body.transactionRef === "string" ? body.transactionRef.trim() : "";
  const grossAtomic = parseAtomic(body.grossAmount);
  const feeAtomic = parseAtomic(body.networkFee ?? "0");
  const receivedAt = parseTimestamp(body.receivedAt);
  const windowStart = parseTimestamp(body.shareWindowStart);
  const windowEnd = parseTimestamp(body.shareWindowEnd);
  const poolHeight = body.poolHeight == null ? null : Number(body.poolHeight);

  if (!/^[A-Za-z0-9:_-]{8,160}$/.test(transactionRef) ||
      grossAtomic == null || grossAtomic <= 0n ||
      feeAtomic == null || feeAtomic < 0n || feeAtomic > grossAtomic ||
      !receivedAt || !windowStart || !windowEnd ||
      Date.parse(windowStart) >= Date.parse(windowEnd) ||
      (poolHeight != null && (!Number.isSafeInteger(poolHeight) || poolHeight < 0))) {
    return NextResponse.json({ error: "Les informations du paiement ou de sa fenêtre de contribution sont invalides." }, { status: 400 });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return NextResponse.json({ error: "La réconciliation des paiements n'est pas configurée." }, { status: 503 });
  }

  const service = createSupabaseClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  const { data: centralWallet, error: walletError } = await service
    .from("central_wallet_identity")
    .select("id")
    .eq("id", true)
    .maybeSingle();

  if (walletError || !centralWallet) {
    return NextResponse.json({ error: "Le wallet central MINE-ME n'est pas encore configuré." }, { status: 409 });
  }

  const payoutInput = {
    central_wallet_id: true,
    transaction_ref: transactionRef,
    gross_amount: formatAtomic(grossAtomic),
    network_fee: formatAtomic(feeAtomic),
    received_at: receivedAt,
    pool_height: poolHeight,
    source: "admin_reconciliation",
    share_window_start: windowStart,
    share_window_end: windowEnd,
  };

  const { error: insertError } = await service
    .from("pool_payouts")
    .upsert(payoutInput, { onConflict: "transaction_ref", ignoreDuplicates: true });

  if (insertError) {
    return NextResponse.json({ error: "Impossible d'enregistrer le paiement central." }, { status: 500 });
  }

  const { data: payout, error: payoutError } = await service
    .from("pool_payouts")
    .select("id, gross_amount, network_fee, received_at, share_window_start, share_window_end")
    .eq("transaction_ref", transactionRef)
    .single();

  if (payoutError || !payout ||
      parseAtomic(String(payout.gross_amount)) !== grossAtomic ||
      parseAtomic(String(payout.network_fee)) !== feeAtomic ||
      Date.parse(payout.received_at) !== Date.parse(receivedAt) ||
      Date.parse(payout.share_window_start) !== Date.parse(windowStart) ||
      Date.parse(payout.share_window_end) !== Date.parse(windowEnd)) {
    return NextResponse.json({ error: "Cette référence de paiement existe déjà avec des données différentes." }, { status: 409 });
  }

  const { data: existingBatch, error: batchLookupError } = await service
    .from("reward_distribution_batches")
    .select("id")
    .eq("payout_id", payout.id)
    .maybeSingle();

  if (batchLookupError) {
    return NextResponse.json({ error: "Impossible de vérifier l'état de la répartition." }, { status: 500 });
  }
  if (existingBatch) {
    return NextResponse.json({ ok: true, alreadyDistributed: true, batchId: existingBatch.id });
  }

  const { data: batchId, error: allocationError } = await service.rpc(
    "reconcile_central_pool_reward_for_window",
    {
      p_transaction_ref: transactionRef,
      p_window_start: windowStart,
      p_window_end: windowEnd,
    },
  );

  if (allocationError || typeof batchId !== "string") {
    return NextResponse.json({
      ok: false,
      payoutRecorded: true,
      allocationPending: true,
      message: "Le paiement central est enregistré. La répartition reste en attente de réconciliation.",
    }, { status: 202 });
  }

  return NextResponse.json({ ok: true, payoutRecorded: true, batchId });
}
