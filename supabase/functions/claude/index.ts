// Claude proxy: the app sends a Messages API body, we add the server's API key and forward it.
// The key never ships on phones. Each signed-in user gets a daily request allowance.

import { adminClient, requireUser } from "../_shared/auth.ts";
import { env, errorResponse, handler, HttpError } from "../_shared/http.ts";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ALLOWED_MODELS = new Set(["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"]);
const ALLOWED_BETAS = new Set(["server-side-fallback-2026-07-01"]);
const MAX_TOKENS = 16_000;

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw new HttpError(405, "Use POST.");
  const userId = await requireUser(req);

  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object") throw new HttpError(400, "Expected a Messages API request body.");
  if (!ALLOWED_MODELS.has(body.model)) throw new HttpError(400, `Model ${body.model} isn't available.`);
  if (typeof body.max_tokens !== "number" || body.max_tokens > MAX_TOKENS) body.max_tokens = MAX_TOKENS;
  delete body.stream;

  const limit = Number(Deno.env.get("CLAUDE_DAILY_LIMIT") ?? "300");
  const { data: used, error } = await adminClient().rpc("record_ai_request", { p_user: userId });
  if (error) throw new HttpError(500, "Couldn't check your AI allowance.");
  if (typeof used === "number" && used > limit) {
    return errorResponse(402, `You've used today's ${limit} AI requests. They reset at midnight UTC.`, "daily_limit");
  }

  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-api-key": env("ANTHROPIC_API_KEY"),
    "anthropic-version": "2023-06-01",
  };
  const beta = req.headers.get("anthropic-beta");
  if (beta && ALLOWED_BETAS.has(beta)) headers["anthropic-beta"] = beta;

  const upstream = await fetch(ANTHROPIC_URL, { method: "POST", headers, body: JSON.stringify(body) });
  // Pass Claude's status and body through untouched so the app's existing error handling applies.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" },
  });
}));
