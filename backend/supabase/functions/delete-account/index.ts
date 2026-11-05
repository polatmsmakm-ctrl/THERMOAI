// =============================================================================
// THERMO AI — Account deletion (Supabase Edge Function)
// File: backend/supabase/functions/delete-account/index.ts
//
// App Store Guideline 5.1.1(v) requires in-app account deletion.
// Verifies the caller's JWT, then deletes the auth user with the service-role
// key. All user tables cascade on auth.users deletion.
//
// SUPABASE_SERVICE_ROLE_KEY is injected automatically into Edge Functions and
// must never be shipped to the client.
// =============================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return respond(405, { error: { code: "method_not_allowed", message: "Use POST" } });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return respond(401, { error: { code: "unauthorized", message: "Missing bearer token" } });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data, error } = await admin.auth.getUser(authHeader.replace("Bearer ", ""));
  if (error || !data?.user) return respond(401, { error: { code: "unauthorized", message: "Invalid session" } });

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    console.error("delete-account failed", deleteError.message);
    return respond(500, { error: { code: "delete_failed", message: "Could not delete account" } });
  }
  return respond(200, { deleted: true });
});

function respond(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
