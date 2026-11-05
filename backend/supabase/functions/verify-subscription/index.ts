// =============================================================================
// THERMO AI — Server-side subscription verification (Supabase Edge Function)
// File: backend/supabase/functions/verify-subscription/index.ts
//
// Sets profiles.is_pro from Apple's App Store Server API so AI quotas can trust it.
//   1. Client sends { originalTransactionId } after a purchase / at launch.
//   2. We query Apple's "Get All Subscription Statuses" endpoint over TLS with
//      an ES256 JWT signed by our In-App Purchase key.
//   3. Pro = any transaction in status 1 (active) or 4 (billing grace period)
//      whose appAccountToken equals the caller's Supabase user id.
//
// Required secrets:
//   APPSTORE_ISSUER_ID     — App Store Connect › Users and Access › Integrations › In-App Purchase
//   APPSTORE_KEY_ID        — key id of the .p8 In-App Purchase key
//   APPSTORE_PRIVATE_KEY   — contents of the .p8 file (PKCS#8 PEM)
//   APPSTORE_BUNDLE_ID     — e.g. com.example.thermoai
// Reference: https://developer.apple.com/documentation/appstoreserverapi
// =============================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT, decodeJwt } from "npm:jose@5";

const PROD = "https://api.storekit.itunes.apple.com";
const SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";
const ACTIVE_STATUSES = new Set([1, 4]);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return respond(405, { error: { code: "method_not_allowed", message: "Use POST" } });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return respond(401, { error: { code: "unauthorized", message: "Missing token" } });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(authHeader.replace("Bearer ", ""));
  if (userError || !userData?.user) return respond(401, { error: { code: "unauthorized", message: "Invalid session" } });
  const userId = userData.user.id.toLowerCase();

  let originalTransactionId: string;
  try {
    const body = await req.json();
    originalTransactionId = String(body.originalTransactionId ?? "");
    if (!/^\d{1,32}$/.test(originalTransactionId)) throw new Error("bad id");
  } catch {
    return respond(400, { error: { code: "bad_request", message: "originalTransactionId required" } });
  }

  try {
    const token = await appStoreToken();
    let res = await fetch(`${PROD}/inApps/v1/subscriptions/${originalTransactionId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) {
      res = await fetch(`${SANDBOX}/inApps/v1/subscriptions/${originalTransactionId}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
    }
    if (!res.ok) {
      console.error("App Store API", res.status, (await res.text()).slice(0, 300));
      return respond(502, { error: { code: "appstore_error", message: "Could not verify subscription" } });
    }

    const payload = await res.json();
    if (payload.bundleId !== Deno.env.get("APPSTORE_BUNDLE_ID")) {
      return respond(403, { error: { code: "bundle_mismatch", message: "Wrong app" } });
    }

    let isPro = false;
    for (const group of payload.data ?? []) {
      for (const tx of group.lastTransactions ?? []) {
        if (!ACTIVE_STATUSES.has(tx.status)) continue;
        // Received directly from Apple over TLS, so decoding without re-verifying is acceptable here.
        const info = decodeJwt(tx.signedTransactionInfo) as { appAccountToken?: string };
        if (info.appAccountToken?.toLowerCase() === userId) isPro = true;
      }
    }

    const { error: updateError } = await admin.from("profiles").update({ is_pro: isPro }).eq("id", userId);
    if (updateError) throw updateError;
    return respond(200, { isPro });
  } catch (err) {
    console.error("verify-subscription failed", err);
    return respond(500, { error: { code: "internal", message: "Verification failed" } });
  }
});

async function appStoreToken(): Promise<string> {
  const key = await importPKCS8(Deno.env.get("APPSTORE_PRIVATE_KEY")!, "ES256");
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({ bid: Deno.env.get("APPSTORE_BUNDLE_ID") })
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APPSTORE_KEY_ID")!, typ: "JWT" })
    .setIssuer(Deno.env.get("APPSTORE_ISSUER_ID")!)
    .setIssuedAt(now)
    .setExpirationTime(now + 15 * 60)
    .setAudience("appstoreconnect-v1")
    .sign(key);
}

function respond(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
