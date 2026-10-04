// Pinterest redirects here after the user approves (no Supabase JWT on this request, so
// verify_jwt is off in config.toml). We check the one-time state, exchange the code with the
// app secret, store the tokens, then hand control back to the app via its URL scheme.

import { adminClient } from "../_shared/auth.ts";
import { HttpError } from "../_shared/http.ts";
import { exchangeCode } from "../_shared/pinterest.ts";

const APP_CALLBACK = Deno.env.get("APP_CALLBACK_URL") ?? "tastedecoder://pinterest";
const STATE_TTL_MS = 10 * 60 * 1000;

function backToApp(params: Record<string, string>): Response {
  const url = `${APP_CALLBACK}?${new URLSearchParams(params)}`;
  return new Response(null, { status: 302, headers: { location: url } });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  if (url.searchParams.get("error")) return backToApp({ error: "denied" });
  if (!state || !code) return backToApp({ error: "missing_code" });

  const admin = adminClient();
  const { data } = await admin.from("oauth_states").delete().eq("state", state).select("user_id, created_at").maybeSingle();
  if (!data || Date.now() - Date.parse(data.created_at) > STATE_TTL_MS) return backToApp({ error: "expired" });

  try {
    await exchangeCode(data.user_id, code);
  } catch (error) {
    console.error(error);
    return backToApp({ error: error instanceof HttpError ? "exchange_failed" : "server" });
  }
  return backToApp({ status: "connected" });
});
