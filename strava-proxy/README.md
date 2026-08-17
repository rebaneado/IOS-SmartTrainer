# Strava token proxy

A one-file Cloudflare Worker that holds your Strava **Client Secret** so it
never ships inside the iOS app. Deploy takes about 5 minutes, no CLI or
account payment required (Cloudflare's free tier covers this easily).

## Deploy

1. Go to <https://dash.cloudflare.com>, sign up free if you don't have an
   account, and open **Workers & Pages**.
2. **Create** → **Create Worker**. Give it any name (e.g. `smarttrainer-strava`).
   Deploy the default "Hello World" — you'll replace the code next.
3. Click **Edit code**. Delete everything and paste in the contents of
   `worker.js` from this folder. Click **Deploy**.
4. Back on the Worker's page, go to **Settings → Variables and Secrets**.
   Add a variable named `STRAVA_CLIENT_SECRET`, type **Secret** (encrypted),
   value = the Client Secret from <https://www.strava.com/settings/api>.
   Save — this redeploys the Worker with the secret attached.
5. Copy the Worker's URL — shown at the top of its page, looks like
   `https://smarttrainer-strava.<your-subdomain>.workers.dev`.
6. In the SmartTrainer app → Settings → Strava, paste that URL into
   **Token proxy URL**, plus your **Client ID** (the non-secret one, also
   from the Strava API settings page). Tap **Connect to Strava**.

That's it — the app never sees or stores your Client Secret; only this
Worker does, and only Cloudflare's servers ever see it in transit between
the app and Strava.

## Why not skip this and just embed the secret in the app?

Plenty of small hobby apps do — it's a common accepted tradeoff when an app
is just for the developer's own use. But once an app is on the App Store,
anyone can download the `.ipa` and pull strings out of the binary, including
a baked-in secret. This proxy is the standard fix: the secret lives on a
server you control, the app only ever holds the public Client ID.
