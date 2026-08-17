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
const ALLOWED_GRANT_TYPES = new Set(["authorization_code", "refresh_token"]);

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response("Invalid JSON body", { status: 400 });
    }

    const { client_id, grant_type, code, refresh_token } = body;
    if (!client_id || !ALLOWED_GRANT_TYPES.has(grant_type)) {
      return new Response("Missing client_id or invalid grant_type", { status: 400 });
    }

    const payload = {
      client_id,
      client_secret: env.STRAVA_CLIENT_SECRET,
      grant_type,
    };
    if (grant_type === "authorization_code") payload.code = code;
    if (grant_type === "refresh_token") payload.refresh_token = refresh_token;

    const stravaResponse = await fetch(STRAVA_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    const text = await stravaResponse.text();
    return new Response(text, {
      status: stravaResponse.status,
      headers: { "Content-Type": "application/json" },
    });
  },
};
