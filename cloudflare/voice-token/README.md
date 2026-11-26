# SCOTT Agora Voice Token Worker

This is an isolated Cloudflare Worker for issuing short-lived Agora RTC tokens. It does not change the SCOTT game client or Firebase room/game logic.

## Required Cloudflare Worker secrets

In **Workers & Pages → scott-voice-token → Settings → Variables and Secrets**, add these as secrets in the **Production** environment:

- `AGORA_APP_ID`: Agora project App ID.
- `AGORA_APP_CERTIFICATE`: Agora project Primary Certificate. Keep this server-side only.
- `FIREBASE_DATABASE_URL`: SCOTT Realtime Database URL, for example `https://scott-5ba9b-default-rtdb.asia-southeast1.firebasedatabase.app`.

Do not add these values to GitHub files, commit messages, or screenshots. `FIREBASE_API_KEY` is not needed by this token Worker.

## Deploy

Set the Cloudflare Worker Git integration root directory to `cloudflare/voice-token`, with build command `npm install` and deploy command `npm run deploy`. Alternatively, deploy this folder with Wrangler from a trusted local environment after installing dependencies.

The Worker name is `scott-voice-token`, matching the Worker created in the Cloudflare dashboard.

Cloudflare Git integration is configured for the `feature/cloudflare-agora-token-server` branch and this directory. A commit to this branch triggers the first build.

## Endpoints

- `GET /health`: non-sensitive health check.
- `POST /rtc-token`: requires a Firebase ID token in `Authorization: Bearer <Firebase-ID-token>` and JSON body `{"roomCode":"ABC123"}`.

The Worker verifies the Firebase ID token for project `scott-5ba9b`, confirms that the Firebase user exists in that room's public player list, then issues a one-hour Agora RTC publisher token. The Agora App Certificate never leaves the Worker.

## Important

This only creates the secure token backend. The SCOTT Android/Web clients still need Agora RTC SDK integration and must call this endpoint with their current Firebase ID token before joining voice chat. That client-side work is intentionally separate from this backend PR.
