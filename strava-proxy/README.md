# Strava token proxy

A one-file Cloudflare Worker that holds your Strava **Client Secret** so it
never ships inside the iOS app. Deploy takes about 5 minutes, no CLI or
account payment required (Cloudflare's free tier covers this easily).

## Deploy

The production Worker is configured in `wrangler.jsonc` as
`ios-smarttrainer`. From this directory, authenticate with Cloudflare and run:

```sh
npx wrangler deploy --dry-run
npx wrangler deploy
```

Wrangler preserves the existing encrypted `STRAVA_CLIENT_SECRET` binding. Do
not place the secret in source, config, command arguments, or shell history.

For a first-time dashboard deployment instead:

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
6. Put the public Worker URL in `StravaTokenProxyURL` and the public Strava
   Client ID in `StravaClientID` in `project.yml`, then regenerate the Xcode
   project. Keep the Client Secret only in Cloudflare.

That's it — riders can tap **Connect to Strava** without entering developer
configuration. The app never sees or stores the Client Secret; only this
Worker does, and only Cloudflare's servers see it during the token exchange.

The included Worker is locked to SmartTrainer's public Client ID, accepts only
the two required OAuth grant types, rejects missing/oversized credentials, and
marks all responses `no-store`.

## Why not skip this and just embed the secret in the app?

Plenty of small hobby apps do — it's a common accepted tradeoff when an app
is just for the developer's own use. But once an app is on the App Store,
anyone can download the `.ipa` and pull strings out of the binary, including
a baked-in secret. This proxy is the standard fix: the secret lives on a
server you control, the app only ever holds the public Client ID.
