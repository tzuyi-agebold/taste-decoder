import { assertEquals } from "jsr:@std/assert@1";
import { boardURL, mapBoard, mapPin, pinImageURL } from "./pinterest.ts";

Deno.test("boardURL slugs the board name", () => {
  assertEquals(boardURL("tzuyi", "Reds I Love"), "https://www.pinterest.com/tzuyi/reds-i-love/");
  assertEquals(boardURL("tzuyi", "Café — Ideas!"), "https://www.pinterest.com/tzuyi/cafe-ideas/");
  assertEquals(boardURL(null, "Rooms"), null);
});

Deno.test("mapBoard keeps what the picker needs", () => {
  const board = mapBoard({
    id: 549755885175,
    name: "Uncomfy",
    description: "  ",
    pin_count: 42,
    privacy: "SECRET",
    media: { image_cover_url: "https://i.pinimg.com/cover.jpg", pin_thumbnail_urls: ["a", "", "b"] },
  }, "tzuyi");
  assertEquals(board.id, "549755885175");
  assertEquals(board.description, null);
  assertEquals(board.pinCount, 42);
  assertEquals(board.privacy, "secret");
  assertEquals(board.coverImageURL, "https://i.pinimg.com/cover.jpg");
  assertEquals(board.thumbnailURLs, ["a", "b"]);
});

Deno.test("pinImageURL handles images, videos and carousels", () => {
  assertEquals(pinImageURL({ images: { "600x": { url: "six" }, "1200x": { url: "twelve" } } }), "six");
  assertEquals(pinImageURL({ images: { "1200x": { url: "twelve" } } }), "twelve");
  assertEquals(pinImageURL({ media_type: "video", cover_image_url: "cover" }), "cover");
  assertEquals(pinImageURL({ media_type: "multiple_images", items: [{ images: { "600x": { url: "first" } } }] }), "first");
  assertEquals(pinImageURL(null), null);
});

Deno.test("mapPin trims empty text to null", () => {
  const pin = mapPin({ id: "1", title: "", description: "Flash portrait", link: null, media: {} });
  assertEquals(pin.title, null);
  assertEquals(pin.description, "Flash portrait");
  assertEquals(pin.imageURL, null);
});
