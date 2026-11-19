"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const CONSENT_VERSION = "2026-11-19-v1";
const STORAGE_KEY = "mine-me.browser-installation-id";

function getInstallationId() {
  let id = window.localStorage.getItem(STORAGE_KEY);
  if (id && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    return id;
  }

  if (typeof window.crypto.randomUUID === "function") {
    id = window.crypto.randomUUID();
  } else {
    const bytes = window.crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, "0"));
    id = [
      hex.slice(0, 4).join(""),
      hex.slice(4, 6).join(""),
      hex.slice(6, 8).join(""),
      hex.slice(8, 10).join(""),
      hex.slice(10, 16).join(""),
    ].join("-");
  }

  window.localStorage.setItem(STORAGE_KEY, id);
  return id;
}

function detectBrowser(userAgent: string) {
  if (/Edg\//i.test(userAgent)) return "Edge";
  if (/Firefox\//i.test(userAgent)) return "Firefox";
  if (/Chrome\//i.test(userAgent) && !/Edg\//i.test(userAgent)) return "Chrome";
  if (/Safari\//i.test(userAgent) && !/Chrome\//i.test(userAgent)) return "Safari";
  return "Navigateur web";
}

function detectPlatform(userAgent: string) {
  if (/Android/i.test(userAgent)) return "Android";
  if (/iPhone|iPad|iPod/i.test(userAgent)) return "iOS";
  if (/Windows/i.test(userAgent)) return "Windows";
  if (/Macintosh|Mac OS/i.test(userAgent)) return "macOS";
  if (/Linux/i.test(userAgent)) return "Linux";
  return "Appareil inconnu";
}

export default function AutoEnrollDevice() {
  const router = useRouter();
  const [message, setMessage] = useState("Association de cet appareil à votre compte…");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;

    async function enroll() {
      try {
        const supabase = createClient();
        const { data: { user }, error: userError } = await supabase.auth.getUser();
        if (userError || !user) throw new Error("Session membre introuvable.");

        const { data: profile, error: profileError } = await supabase
          .from("profiles")
          .select("consent_version, consented_at, account_status")
          .eq("id", user.id)
          .single();

        if (profileError || profile?.account_status !== "active" || !profile?.consented_at || profile.consent_version !== CONSENT_VERSION) {
          throw new Error("Le consentement actuel est requis avant l’association de l’appareil.");
        }

        const installationId = getInstallationId();
        const userAgent = navigator.userAgent;
        const browser = detectBrowser(userAgent);
        const platform = detectPlatform(userAgent);
        const threads = Math.max(1, Math.min(256, navigator.hardwareConcurrency || 1));
        const label = `${platform} · ${browser}`;

        const { data: existing, error: lookupError } = await supabase
          .from("devices")
          .select("id, worker_code")
          .eq("user_id", user.id)
          .eq("installation_id", installationId)
          .maybeSingle();

        if (lookupError) throw lookupError;

        if (existing) {
          const { error: updateError } = await supabase
            .from("devices")
            .update({
              label,
              browser_family: browser,
              platform_family: platform,
              hardware_threads: threads,
              last_seen_at: new Date().toISOString(),
            })
            .eq("id", existing.id)
            .eq("user_id", user.id);

          if (updateError) throw updateError;
        } else {
          const { data: enrolledDevice, error: insertError } = await supabase
            .from("devices")
            .insert({
              user_id: user.id,
              installation_id: installationId,
              label,
              browser_family: browser,
              platform_family: platform,
              hardware_threads: threads,
              last_seen_at: new Date().toISOString(),
            })
            .select("id")
            .single();

          if (insertError && insertError.code !== "23505") throw insertError;

          if (enrolledDevice?.id) {
            const { error: eventError } = await supabase.from("device_events").insert({
              device_id: enrolledDevice.id,
              event_type: "enrolled",
              details: { source: "browser_registration", browser, platform, hardware_threads: threads },
            });
            if (eventError) throw eventError;
          }
          // A second tab can win the unique insert race. The next dashboard refresh
          // will find and update that existing installation rather than duplicating it.
        }

        if (active) {
          setFailed(false);
          setMessage("Cet appareil est associé à votre compte. Le minage reste désactivé jusqu’à la validation du moteur et du pool.");
          router.refresh();
        }
      } catch {
        if (active) {
          setFailed(true);
          setMessage("L’association automatique de cet appareil n’a pas abouti. Votre compte reste accessible ; réessayez après vérification de la configuration.");
        }
      }
    }

    void enroll();
    return () => {
      active = false;
    };
  }, [router]);

  return <p className={failed ? "enrollment-message enrollment-error" : "enrollment-message"} role="status">{message}</p>;
}
