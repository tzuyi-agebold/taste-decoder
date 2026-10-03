import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { env, HttpError } from "./http.ts";

/** Service-role client for server-only tables (tokens, OAuth state, usage). Never expose it to the app. */
export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Verifies the caller's Supabase session and returns their user id. */
export async function requireUser(req: Request): Promise<string> {
  const header = req.headers.get("authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  if (!token) throw new HttpError(401, "Sign in to use this feature.");
  const { data, error } = await adminClient().auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "Your session has expired. Sign in again.");
  return data.user.id;
}
