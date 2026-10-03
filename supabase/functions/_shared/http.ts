// Small HTTP helpers shared by the Edge Functions.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, anthropic-beta",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

/** Errors use the same envelope as the Claude API so the app can show `error.message` everywhere. */
export function errorResponse(status: number, message: string, type = "error"): Response {
  return json({ type: "error", error: { type, message } }, status);
}

export function preflight(req: Request): Response | null {
  return req.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}

export function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new HttpError(500, `Server is missing the ${name} secret.`);
  return value;
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** Wraps a handler so thrown HttpErrors become JSON error responses. */
export function handler(fn: (req: Request) => Promise<Response>): (req: Request) => Promise<Response> {
  return async (req) => {
    const early = preflight(req);
    if (early) return early;
    try {
      return await fn(req);
    } catch (error) {
      if (error instanceof HttpError) return errorResponse(error.status, error.message);
      console.error(error);
      return errorResponse(500, "Something went wrong on the server.");
    }
  };
}
