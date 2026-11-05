// =============================================================================
// THERMO AI — Gemini backend proxy (Supabase Edge Function, Deno runtime)
// File: backend/supabase/functions/gemini-proxy/index.ts
//
// Purpose:
//   The ONLY place the Gemini API key exists. The iOS app calls this function
//   with the user's Supabase JWT; the function authenticates the user, enforces
//   a daily quota, calls Gemini with a strict JSON schema, validates and
//   sanitises the response, then returns typed JSON to the app.
//
// Endpoint:  POST {SUPABASE_URL}/functions/v1/gemini-proxy
// Body:      { "task": "analyzeFoodImage" | "analyzeFoodText" | "chat" | "mealPlan", ...payload }
//
// Required secrets (set with `supabase secrets set`):
//   GEMINI_API_KEY      — Google AI Studio key (never shipped to the client)
//   GEMINI_MODEL        — optional, defaults to "gemini-3.5-flash"
//   AI_FREE_DAILY_LIMIT — optional, default 25
//   AI_PRO_DAILY_LIMIT  — optional, default 300
// SUPABASE_URL and SUPABASE_ANON_KEY are injected automatically by Supabase.
//
// Gemini REST reference: POST /v1beta/models/{model}:generateContent with
// generationConfig.responseMimeType = "application/json" and
// generationConfig.responseJsonSchema (JSON Schema). Verify against
// https://ai.google.dev/gemini-api/docs/json-mode before deploying.
// =============================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  FOOD_ANALYSIS_SCHEMA,
  CHAT_SCHEMA,
  MEAL_PLAN_SCHEMA,
} from "./schemas.ts";
import {
  validateFoodAnalysis,
  validateChatReply,
  validateMealPlan,
  ValidationError,
} from "./validation.ts";
import {
  FOOD_IMAGE_SYSTEM_PROMPT,
  FOOD_TEXT_SYSTEM_PROMPT,
  CHAT_SYSTEM_PROMPT,
  MEAL_PLAN_SYSTEM_PROMPT,
} from "./prompts.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.5-flash";
const FREE_LIMIT = Number(Deno.env.get("AI_FREE_DAILY_LIMIT") ?? "25");
const PRO_LIMIT = Number(Deno.env.get("AI_PRO_DAILY_LIMIT") ?? "300");
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const MAX_IMAGE_BASE64_BYTES = 6 * 1024 * 1024; // ~4.5 MB binary
const MAX_TEXT_CHARS = 4000;
const MAX_CHAT_TURNS = 20;
const GEMINI_TIMEOUT_MS = 45_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
type Task = "analyzeFoodImage" | "analyzeFoodText" | "chat" | "mealPlan";

interface ChatTurn { role: "user" | "assistant"; text: string }

interface NutritionContext {
  targetCalories?: number;
  consumedCalories?: number;
  proteinTargetG?: number;
  carbsTargetG?: number;
  fatTargetG?: number;
  goal?: string;
}

interface RequestBody {
  task: Task;
  imageBase64?: string;
  mimeType?: string;
  description?: string;
  note?: string;
  messages?: ChatTurn[];
  context?: NutritionContext;
  targets?: { calories: number; proteinG: number; carbsG: number; fatG: number };
  preferences?: { diet?: string; allergies?: string[]; dislikes?: string[]; cuisines?: string[] };
  days?: number;
}

class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Use POST");
    if (!GEMINI_API_KEY) throw new HttpError(500, "server_misconfigured", "GEMINI_API_KEY is not set");

    // 1. Authenticate the caller with their own JWT (RLS applies to this client).
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      throw new HttpError(401, "unauthorized", "Missing bearer token");
    }
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData?.user) throw new HttpError(401, "unauthorized", "Invalid session");

    // 2. Parse and validate the request body.
    let body: RequestBody;
    try {
      body = await req.json();
    } catch {
      throw new HttpError(400, "bad_request", "Body must be JSON");
    }
    validateRequest(body);

    // 3. Enforce the per-user daily quota.
    const { data: allowed, error: quotaError } = await supabase.rpc("consume_ai_quota", {
      p_free_limit: FREE_LIMIT,
      p_pro_limit: PRO_LIMIT,
    });
    if (quotaError) throw new HttpError(500, "quota_error", quotaError.message);
    if (allowed !== true) throw new HttpError(429, "quota_exceeded", "Daily AI limit reached");

    // 4. Dispatch.
    const result = await handleTask(body);
    return json(200, result);
  } catch (err) {
    if (err instanceof HttpError) return json(err.status, { error: { code: err.code, message: err.message } });
    if (err instanceof ValidationError) {
      return json(502, { error: { code: "invalid_ai_response", message: err.message } });
    }
    console.error("gemini-proxy unexpected error", err);
    return json(500, { error: { code: "internal", message: "Unexpected server error" } });
  }
});

// ---------------------------------------------------------------------------
// Request validation
// ---------------------------------------------------------------------------
function validateRequest(body: RequestBody): void {
  const tasks: Task[] = ["analyzeFoodImage", "analyzeFoodText", "chat", "mealPlan"];
  if (!body || !tasks.includes(body.task)) throw new HttpError(400, "bad_request", "Unknown task");

  switch (body.task) {
    case "analyzeFoodImage": {
      if (typeof body.imageBase64 !== "string" || body.imageBase64.length === 0) {
        throw new HttpError(400, "bad_request", "imageBase64 required");
      }
      if (body.imageBase64.length > MAX_IMAGE_BASE64_BYTES) {
        throw new HttpError(413, "payload_too_large", "Image too large");
      }
      const allowedMime = ["image/jpeg", "image/png", "image/heic", "image/webp"];
      if (!allowedMime.includes(body.mimeType ?? "")) {
        throw new HttpError(400, "bad_request", "Unsupported image type");
      }
      if (body.note && body.note.length > 500) throw new HttpError(400, "bad_request", "note too long");
      break;
    }
    case "analyzeFoodText":
      if (typeof body.description !== "string" || body.description.trim().length === 0) {
        throw new HttpError(400, "bad_request", "description required");
      }
      if (body.description.length > MAX_TEXT_CHARS) throw new HttpError(400, "bad_request", "description too long");
      break;
    case "chat":
      if (!Array.isArray(body.messages) || body.messages.length === 0) {
        throw new HttpError(400, "bad_request", "messages required");
      }
      if (body.messages.length > MAX_CHAT_TURNS * 2) throw new HttpError(400, "bad_request", "conversation too long");
      for (const m of body.messages) {
        if ((m.role !== "user" && m.role !== "assistant") || typeof m.text !== "string" || m.text.length > MAX_TEXT_CHARS) {
          throw new HttpError(400, "bad_request", "invalid message");
        }
      }
      break;
    case "mealPlan": {
      const t = body.targets;
      if (!t || ![t.calories, t.proteinG, t.carbsG, t.fatG].every((n) => Number.isFinite(n) && n >= 0)) {
        throw new HttpError(400, "bad_request", "targets required");
      }
      if (t.calories < 1000 || t.calories > 6000) throw new HttpError(400, "bad_request", "calories out of range");
      const days = body.days ?? 1;
      if (!Number.isInteger(days) || days < 1 || days > 7) throw new HttpError(400, "bad_request", "days must be 1-7");
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// Task handlers
// ---------------------------------------------------------------------------
async function handleTask(body: RequestBody): Promise<unknown> {
  switch (body.task) {
    case "analyzeFoodImage": {
      const parts = [
        { inlineData: { mimeType: body.mimeType!, data: body.imageBase64! } },
        { text: body.note ? `User note: ${sanitize(body.note)}` : "Analyze this meal." },
      ];
      const raw = await callGemini(FOOD_IMAGE_SYSTEM_PROMPT, [{ role: "user", parts }], FOOD_ANALYSIS_SCHEMA, 0.2);
      return validateFoodAnalysis(raw);
    }
    case "analyzeFoodText": {
      const parts = [{ text: `Meal description: ${sanitize(body.description!)}` }];
      const raw = await callGemini(FOOD_TEXT_SYSTEM_PROMPT, [{ role: "user", parts }], FOOD_ANALYSIS_SCHEMA, 0.2);
      return validateFoodAnalysis(raw);
    }
    case "chat": {
      const contextText = body.context ? `\n\nUser context (JSON): ${JSON.stringify(body.context)}` : "";
      const contents = body.messages!.slice(-MAX_CHAT_TURNS * 2).map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [{ text: sanitize(m.text) }],
      }));
      const raw = await callGemini(CHAT_SYSTEM_PROMPT + contextText, contents, CHAT_SCHEMA, 0.6);
      return validateChatReply(raw);
    }
    case "mealPlan": {
      const prompt = JSON.stringify({
        targets: body.targets,
        preferences: body.preferences ?? {},
        days: body.days ?? 1,
      });
      const raw = await callGemini(
        MEAL_PLAN_SYSTEM_PROMPT,
        [{ role: "user", parts: [{ text: `Create a meal plan for: ${prompt}` }] }],
        MEAL_PLAN_SCHEMA,
        0.7,
      );
      return validateMealPlan(raw, body.targets!, body.days ?? 1);
    }
  }
}

// ---------------------------------------------------------------------------
// Gemini call
// ---------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
async function callGemini(systemPrompt: string, contents: any[], schema: object, temperature: number): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);

  try {
    const response = await fetch(GEMINI_ENDPOINT, {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents,
        generationConfig: {
          temperature,
          responseMimeType: "application/json",
          responseJsonSchema: schema,
        },
      }),
    });

    if (response.status === 429) throw new HttpError(503, "ai_busy", "AI service is busy, retry shortly");
    if (!response.ok) {
      const detail = await response.text();
      console.error("Gemini error", response.status, detail.slice(0, 500));
      throw new HttpError(502, "ai_upstream_error", `AI provider returned ${response.status}`);
    }

    const payload = await response.json();
    const candidate = payload?.candidates?.[0];
    if (!candidate) {
      const blocked = payload?.promptFeedback?.blockReason;
      throw new HttpError(422, "ai_blocked", blocked ? `Request blocked: ${blocked}` : "No AI response");
    }
    if (candidate.finishReason && !["STOP", "MAX_TOKENS"].includes(candidate.finishReason)) {
      throw new HttpError(422, "ai_blocked", `AI stopped: ${candidate.finishReason}`);
    }

    const text: string = (candidate.content?.parts ?? [])
      .map((p: { text?: string }) => p.text ?? "")
      .join("");
    try {
      return JSON.parse(text);
    } catch {
      throw new ValidationError("AI returned malformed JSON");
    }
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") {
      throw new HttpError(504, "ai_timeout", "AI request timed out");
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
/** Strips control characters; user text is always passed as data, never as instructions. */
function sanitize(input: string): string {
  // deno-lint-ignore no-control-regex
  return input.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").slice(0, MAX_TEXT_CHARS);
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
