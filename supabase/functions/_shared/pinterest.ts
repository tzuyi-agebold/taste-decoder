// Pinterest API v5 client. Tokens live in `pinterest_connections` and never leave the server.

import { adminClient } from "./auth.ts";
import { env, HttpError } from "./http.ts";

export const PINTEREST_API = "https://api.pinterest.com/v5";
export const PINTEREST_AUTHORIZE = "https://www.pinterest.com/oauth/";
export const SCOPES = ["user_accounts:read", "boards:read", "pins:read", "boards:read_secret", "pins:read_secret"];
/** Upper bound on pins read per board; enough for a confident summary without long imports. */
export const MAX_PINS = 250;

export function redirectURI(): string {
  return Deno.env.get("PINTEREST_REDIRECT_URI") ?? `${env("SUPABASE_URL")}/functions/v1/pinterest-callback`;
}

export function authorizeURL(state: string): string {
  const params = new URLSearchParams({
    client_id: env("PINTEREST_APP_ID"),
    redirect_uri: redirectURI(),
    response_type: "code",
    scope: SCOPES.join(","),
    state,
  });
  return `${PINTEREST_AUTHORIZE}?${params}`;
}

// MARK: - Tokens

interface TokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
  refresh_token_expires_in?: number;
  scope?: string;
}

async function tokenRequest(form: Record<string, string>): Promise<TokenResponse> {
  const basic = btoa(`${env("PINTEREST_APP_ID")}:${env("PINTEREST_APP_SECRET")}`);
  const response = await fetch(`${PINTEREST_API}/oauth/token`, {
    method: "POST",
    headers: { authorization: `Basic ${basic}`, "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
  });
  if (!response.ok) {
    console.error("Pinterest token error", response.status, await response.text());
    throw new HttpError(502, "Pinterest didn't accept the sign-in. Try connecting again.");
  }
  return await response.json();
}

function expiry(seconds?: number): string | null {
  return seconds ? new Date(Date.now() + seconds * 1000).toISOString() : null;
}

export async function exchangeCode(userId: string, code: string): Promise<void> {
  const token = await tokenRequest({ grant_type: "authorization_code", code, redirect_uri: redirectURI() });
  const username = await fetchUsername(token.access_token);
  const { error } = await adminClient().from("pinterest_connections").upsert({
    user_id: userId,
    access_token: token.access_token,
    refresh_token: token.refresh_token ?? null,
    expires_at: expiry(token.expires_in),
    refresh_expires_at: expiry(token.refresh_token_expires_in),
    scope: token.scope ?? null,
    pinterest_username: username,
  });
  if (error) throw new HttpError(500, "Couldn't save the Pinterest connection.");
}

async function fetchUsername(accessToken: string): Promise<string | null> {
  const response = await fetch(`${PINTEREST_API}/user_account`, { headers: { authorization: `Bearer ${accessToken}` } });
  if (!response.ok) return null;
  const account = await response.json();
  return typeof account.username === "string" ? account.username : null;
}

interface Connection {
  access_token: string;
  refresh_token: string | null;
  expires_at: string | null;
  pinterest_username: string | null;
}

/** A valid access token for the user, refreshed when it's about to expire. */
async function connection(userId: string): Promise<Connection> {
  const admin = adminClient();
  const { data } = await admin.from("pinterest_connections")
    .select("access_token, refresh_token, expires_at, pinterest_username")
    .eq("user_id", userId)
    .maybeSingle();
  if (!data) throw new HttpError(409, "Connect Pinterest first.");

  const expiresAt = data.expires_at ? Date.parse(data.expires_at) : Infinity;
  if (expiresAt - Date.now() > 60_000) return data;
  if (!data.refresh_token) throw new HttpError(409, "Your Pinterest connection expired. Connect again.");

  const token = await tokenRequest({ grant_type: "refresh_token", refresh_token: data.refresh_token });
  const refreshed = {
    access_token: token.access_token,
    refresh_token: token.refresh_token ?? data.refresh_token,
    expires_at: expiry(token.expires_in),
  };
  await admin.from("pinterest_connections").update(refreshed).eq("user_id", userId);
  return { ...data, ...refreshed };
}

export async function pinterestGet(userId: string, path: string, query: Record<string, string> = {}) {
  const { access_token } = await connection(userId);
  const url = new URL(`${PINTEREST_API}${path}`);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
  const response = await fetch(url, { headers: { authorization: `Bearer ${access_token}` } });
  if (response.status === 401) throw new HttpError(409, "Your Pinterest connection expired. Connect again.");
  if (response.status === 429) throw new HttpError(429, "Pinterest is rate-limiting requests. Try again in a minute.");
  if (!response.ok) {
    console.error("Pinterest API error", path, response.status, await response.text());
    throw new HttpError(502, `Pinterest returned an error (${response.status}).`);
  }
  return await response.json();
}

export async function username(userId: string): Promise<string | null> {
  return (await connection(userId)).pinterest_username;
}

// MARK: - Response mapping (pure; covered by tests)

export interface Board {
  id: string;
  name: string;
  description: string | null;
  pinCount: number;
  privacy: string;
  coverImageURL: string | null;
  thumbnailURLs: string[];
  url: string | null;
}

export interface Pin {
  id: string;
  title: string | null;
  description: string | null;
  link: string | null;
  altText: string | null;
  dominantColor: string | null;
  imageURL: string | null;
}

// deno-lint-ignore no-explicit-any
type Raw = any;

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

/** Pinterest board URLs are /{username}/{slug}/; the slug is derived from the name. */
export function boardURL(username: string | null, name: string): string | null {
  if (!username) return null;
  const slug = name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return slug ? `https://www.pinterest.com/${username}/${slug}/` : `https://www.pinterest.com/${username}/`;
}

export function mapBoard(raw: Raw, username: string | null): Board {
  const name = text(raw.name) ?? "Untitled board";
  return {
    id: String(raw.id),
    name,
    description: text(raw.description),
    pinCount: Number(raw.pin_count ?? 0),
    privacy: text(raw.privacy)?.toLowerCase() ?? "public",
    coverImageURL: text(raw.media?.image_cover_url),
    thumbnailURLs: Array.isArray(raw.media?.pin_thumbnail_urls) ? raw.media.pin_thumbnail_urls.filter(text) : [],
    url: boardURL(username, name),
  };
}

/** The best mid-size image for a pin: still images, video covers, and the first image of carousels. */
export function pinImageURL(media: Raw): string | null {
  if (!media) return null;
  const pick = (images: Raw) =>
    text(images?.["600x"]?.url) ?? text(images?.["1200x"]?.url) ?? text(images?.["400x300"]?.url) ??
      text(images?.["150x150"]?.url);
  return pick(media.images) ?? text(media.cover_image_url) ??
    (Array.isArray(media.items) ? pick(media.items[0]?.images) ?? text(media.items[0]?.cover_image_url) : null);
}

export function mapPin(raw: Raw): Pin {
  return {
    id: String(raw.id),
    title: text(raw.title),
    description: text(raw.description),
    link: text(raw.link),
    altText: text(raw.alt_text),
    dominantColor: text(raw.dominant_color),
    imageURL: pinImageURL(raw.media),
  };
}
