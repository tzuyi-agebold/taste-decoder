// Starts Pinterest OAuth: records a one-time state for the signed-in user and returns the authorize URL.
// The app opens it in ASWebAuthenticationSession; Pinterest then calls pinterest-callback.

import { adminClient, requireUser } from "../_shared/auth.ts";
import { handler, HttpError, json } from "../_shared/http.ts";
import { authorizeURL } from "../_shared/pinterest.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const state = crypto.randomUUID() + crypto.randomUUID().replaceAll("-", "");
  const admin = adminClient();
  // Drop this user's stale attempts before adding a new one.
  await admin.from("oauth_states").delete().eq("user_id", userId);
  const { error } = await admin.from("oauth_states").insert({ state, user_id: userId, provider: "pinterest" });
  if (error) throw new HttpError(500, "Couldn't start connecting Pinterest.");
  return json({ url: authorizeURL(state) });
}));
