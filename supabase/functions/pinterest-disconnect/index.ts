// Forgets the user's Pinterest tokens. Imported collections stay.

import { adminClient, requireUser } from "../_shared/auth.ts";
import { handler, json } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  await adminClient().from("pinterest_connections").delete().eq("user_id", userId);
  return json({ connected: false });
}));
