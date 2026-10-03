// Lists pins on one board, newest first, capped at MAX_PINS.
// Body: { "boardId": "..." }

import { requireUser } from "../_shared/auth.ts";
import { handler, HttpError, json } from "../_shared/http.ts";
import { mapPin, MAX_PINS, type Pin, pinterestGet } from "../_shared/pinterest.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const { boardId } = await req.json().catch(() => ({}));
  if (typeof boardId !== "string" || !/^\d+$/.test(boardId)) throw new HttpError(400, "Pick a board to import.");

  const pins: Pin[] = [];
  let bookmark: string | null = null;
  do {
    const page = await pinterestGet(userId, `/boards/${boardId}/pins`, {
      page_size: "100",
      ...(bookmark ? { bookmark } : {}),
    });
    for (const raw of page.items ?? []) pins.push(mapPin(raw));
    bookmark = page.bookmark ?? null;
  } while (bookmark && pins.length < MAX_PINS);
  return json({ pins: pins.slice(0, MAX_PINS), truncated: bookmark !== null });
}));
