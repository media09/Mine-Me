import { createHmac, randomUUID } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const CONSENT_VERSION = "2026-11-19-v1";
const TOKEN_ISSUER = "mine-me-web";
const TOKEN_AUDIENCE = "mine-me-pool-gateway";
const TOKEN_TTL_SECONDS = 90;

function signToken(payload: Record<string, unknown>, secret: string) {
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = createHmac("sha256", secret).update(encoded).digest("base64url");
  return `${encoded}.${signature}`;
}

function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: { "Cache-Control": "no-store" } });
}

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return jsonError("Vous devez être connecté pour démarrer votre appareil.", 401);

    const body = await request.json().catch(() => null) as { deviceId?: unknown } | null;
    if (!body || typeof body.deviceId !== "string" || !/^[0-9a-f-]{36}$/i.test(body.deviceId)) {
      return jsonError("Identifiant d’appareil invalide.", 400);
    }

    const secret = process.env.MINING_GATEWAY_TOKEN_SECRET;
    const gatewayUrl = process.env.MINING_GATEWAY_PUBLIC_URL;
    if (!secret || Buffer.byteLength(secret) < 32 || !gatewayUrl) {
      return jsonError("Le service de calcul n’est pas encore configuré sur le serveur.", 503);
    }

    let parsedGatewayUrl: URL;
    try {
      parsedGatewayUrl = new URL(gatewayUrl);
    } catch {
      return jsonError("L’adresse du service de calcul est invalide.", 503);
    }
    if (
      parsedGatewayUrl.protocol !== "wss:" &&
      !(process.env.NODE_ENV !== "production" && parsedGatewayUrl.protocol === "ws:")
    ) {
      return jsonError("Le service de calcul doit utiliser une connexion WebSocket sécurisée.", 503);
    }

    const [profileResult, deviceResult, settingsResult] = await Promise.all([
      supabase.from("profiles")
        .select("id, account_status, consent_version, consented_at")
        .eq("id", user.id)
        .maybeSingle(),
      supabase.from("devices")
        .select("id, user_id, worker_code, status, intensity_percent")
        .eq("id", body.deviceId)
        .eq("user_id", user.id)
        .maybeSingle(),
      supabase.from("platform_settings")
        .select("key, value")
        .in("key", ["mining_enabled", "global_emergency_pause", "global_max_intensity_percent"]),
    ]);

    if (profileResult.error || deviceResult.error || settingsResult.error) {
      return jsonError("Impossible de vérifier l’autorisation de cet appareil.", 503);
    }

    const profile = profileResult.data;
    const device = deviceResult.data;
    if (!profile || !device) return jsonError("Compte ou appareil introuvable.", 404);
    if (profile.account_status !== "active") return jsonError("Votre compte est suspendu.", 403);
    if (profile.consent_version !== CONSENT_VERSION || !profile.consented_at) {
      return jsonError("Votre consentement actuel est requis.", 403);
    }

    const settings = new Map((settingsResult.data ?? []).map((row) => [row.key, row.value]));
    if (settings.get("mining_enabled") !== true) {
      return jsonError("Le minage du navigateur n’est pas encore activé par l’administration.", 409);
    }
    if (settings.get("global_emergency_pause") !== false) {
      return jsonError("La pause de sécurité globale est activée.", 409);
    }

    const maxIntensityValue = Number(settings.get("global_max_intensity_percent") ?? 80);
    const maxIntensity = Number.isFinite(maxIntensityValue)
      ? Math.min(80, Math.max(1, Math.trunc(maxIntensityValue)))
      : 80;
    const intensityPercent = Math.min(maxIntensity, Math.max(1, Math.min(80, device.intensity_percent)));

    // A normal tab close is marked offline by the gateway. Returning to the app
    // re-enrols that device, but paused/stopped devices require an explicit user action.
    if (device.status === "offline") {
      const { data: resumed, error: resumeError } = await supabase
        .from("devices")
        .update({ status: "enrolled", last_seen_at: new Date().toISOString() })
        .eq("id", device.id)
        .eq("user_id", user.id)
        .eq("status", "offline")
        .select("id, status")
        .maybeSingle();
      if (resumeError || !resumed || resumed.status !== "enrolled") {
        return jsonError("Cet appareil n’a pas pu être réactivé. Actualisez votre espace.", 409);
      }
    } else if (device.status !== "enrolled") {
      return jsonError("Cet appareil est en pause ou arrêté. Réactivez-le depuis votre espace membre.", 409);
    }

    const issuedAt = Math.floor(Date.now() / 1000);
    const payload = {
      iss: TOKEN_ISSUER,
      aud: TOKEN_AUDIENCE,
      sub: user.id,
      deviceId: device.id,
      workerCode: device.worker_code,
      consentVersion: CONSENT_VERSION,
      intensityPercent,
      iat: issuedAt,
      exp: issuedAt + TOKEN_TTL_SECONDS,
      jti: randomUUID(),
    };

    const token = signToken(payload, secret);
    return NextResponse.json({
      token,
      gatewayUrl: parsedGatewayUrl.toString(),
      workerCode: device.worker_code,
      intensityPercent,
      expiresAt: payload.exp,
    }, { headers: { "Cache-Control": "no-store", Pragma: "no-cache" } });
  } catch {
    return jsonError("Une erreur est survenue lors de la préparation de la session de calcul.", 500);
  }
}
