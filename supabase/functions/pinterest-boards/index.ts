// Lists the signed-in user's Pinterest boards (all pages).

import { requireUser } from "../_shared/auth.ts";
import { handler, json } from "../_shared/http.ts";
import { type Board, mapBoard, pinterestGet, username } from "../_shared/pinterest.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const owner = await username(userId);
  const boards: Board[] = [];
  let bookmark: string | null = null;
  do {
    const page = await pinterestGet(userId, "/boards", {
      page_size: "100",
      privacy: "ALL",
      ...(bookmark ? { bookmark } : {}),
    });
    for (const raw of page.items ?? []) boards.push(mapBoard(raw, owner));
    bookmark = page.bookmark ?? null;
  } while (bookmark && boards.length < 1000);
  return json({ username: owner, boards });
}));
