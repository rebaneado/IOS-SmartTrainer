// SmartTrainer Strava token proxy — a Cloudflare Worker.
//
// Why this exists: Strava's OAuth token exchange requires a Client Secret.
// If that secret were embedded in the iOS app, anyone who downloads the app
// from the App Store could extract it from the binary. This tiny proxy holds
// the secret server-side (as a Cloudflare "secret" environment variable, never
// in this file) so the app only ever ships its public Client ID.
//
// The app POSTs { client_id, grant_type, code } or
// { client_id, grant_type, refresh_token } here; this worker adds the
// client_secret and forwards to Strava, then relays Strava's response back
// unchanged. It never stores anything — every request is stateless.
//
// Deploy: paste this file into a new Worker at https://dash.cloudflare.com
// (Workers & Pages -> Create -> Create Worker -> Edit code), then add an
// environment variable/secret named STRAVA_CLIENT_SECRET with your Strava
// app's Client Secret (Settings -> Variables -> "Encrypt" it). Free tier is
// plenty for one rider's app.

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";
const STRAVA_CLIENT_ID = "272801"; // Public OAuth application identifier.
const ALLOWED_GRANT_TYPES = new Set(["authorization_code", "refresh_token"]);
const MAX_BODY_BYTES = 4096;

function response(body, status, contentType = "text/plain; charset=utf-8") {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

async function readBoundedBody(request) {
  if (!request.body) return { text: "" };

  const reader = request.body.getReader();
  const chunks = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      totalBytes += value.byteLength;
      if (totalBytes > MAX_BODY_BYTES) {
        await reader.cancel();
        return { tooLarge: true };
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { text: new TextDecoder().decode(bytes) };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/") {
      return response("Not found", 404);
    }
    if (request.method !== "POST") {
      return response("Method not allowed", 405);
    }
    if (!request.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) {
      return response("Content-Type must be application/json", 415);
    }
    const declaredLength = Number(request.headers.get("Content-Length") ?? 0);
    if (declaredLength > MAX_BODY_BYTES) {
      return response("Request body too large", 413);
    }

    let body;
    try {
      const bodyResult = await readBoundedBody(request);
      if (bodyResult.tooLarge) {
        return response("Request body too large", 413);
      }
      body = JSON.parse(bodyResult.text);
    } catch {
      return response("Invalid JSON body", 400);
    }

    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return response("Invalid JSON body", 400);
    }

    const { client_id, grant_type, code, refresh_token } = body;
    if (String(client_id) !== STRAVA_CLIENT_ID || !ALLOWED_GRANT_TYPES.has(grant_type)) {
      return response("Invalid OAuth request", 400);
    }
    const credential = grant_type === "authorization_code" ? code : refresh_token;
    if (typeof credential !== "string" || credential.length < 1 || credential.length > 2048) {
      return response("Missing or invalid OAuth credential", 400);
    }
    if (!env.STRAVA_CLIENT_SECRET) {
      return response("Service unavailable", 503);
    }

    const payload = {
      client_id: STRAVA_CLIENT_ID,
      client_secret: env.STRAVA_CLIENT_SECRET,
      grant_type,
    };
    if (grant_type === "authorization_code") payload.code = code;
    if (grant_type === "refresh_token") payload.refresh_token = refresh_token;

    let stravaResponse;
    try {
      stravaResponse = await fetch(STRAVA_TOKEN_URL, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });
    } catch {
      return response("Upstream service unavailable", 502);
    }

    return response(
      stravaResponse.body,
      stravaResponse.status,
      "application/json; charset=utf-8",
    );
  },
};
