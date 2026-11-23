import { RtcTokenBuilder, RtcRole } from "agora-token";
import { createRemoteJWKSet, jwtVerify } from "jose";

const FIREBASE_PROJECT_ID = "scott-5ba9b";
const FIREBASE_JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com")
);
const TOKEN_TTL_SECONDS = 60 * 60;

function json(data, status = 200, origin = "*") {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": origin,
      "vary": "Origin"
    }
  });
}

function corsHeaders(origin = "*") {
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, GET, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-max-age": "86400",
    "vary": "Origin"
  };
}

async function authenticateFirebaseUser(request) {
  const authorization = request.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\\s+(.+)$/i);
  if (!match) throw new Error("Firebase sign-in required.");
  const { payload } = await jwtVerify(match[1], FIREBASE_JWKS, {
    issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
    audience: FIREBASE_PROJECT_ID,
    algorithms: ["RS256"]
  });
  if (typeof payload.sub !== "string" || payload.sub.length < 1 || payload.sub.length > 128) {
    throw new Error("Invalid Firebase user.");
  }
  return { uid: payload.sub, idToken: match[1] };
}

async function makeAgoraUid(firebaseUid) {
  const bytes = new TextEncoder().encode(firebaseUid);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const value = new DataView(digest).getUint32(0, false) & 0x7fffffff;
  return value || 1;
}

async function getRoomPlayers(databaseUrl, roomCode, idToken) {
  const base = databaseUrl.replace(/\\/+$/, "");
  const url = `${base}/rooms/${encodeURIComponent(roomCode)}/public/players.json?auth=${encodeURIComponent(idToken)}`;
  const response = await fetch(url, { headers: { accept: "application/json" } });
  if (!response.ok) throw new Error("Unable to verify SCOTT room membership.");
  const raw = await response.json();
  if (!raw || typeof raw !== "object") return [];
  return Promise.all(Object.entries(raw).map(async ([firebaseUid, player]) => ({
    uid: await makeAgoraUid(firebaseUid),
    name: typeof player?.name === "string" && player.name.trim() ? player.name.trim().slice(0, 24) : "खिलाड़ी"
  })));
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("origin") || "*";
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "scott-voice-token" }, 200, origin);
    }
    if (request.method !== "POST" || url.pathname !== "/rtc-token") {
      return json({ error: "Not found" }, 404, origin);
    }
    if (!env.AGORA_APP_ID || !env.AGORA_APP_CERTIFICATE || !env.FIREBASE_DATABASE_URL) {
      return json({ error: "Server configuration is incomplete." }, 503, origin);
    }
    try {
      const user = await authenticateFirebaseUser(request);
      const body = await request.json();
      const roomCode = typeof body.roomCode === "string" ? body.roomCode.trim().toUpperCase() : "";
      if (!/^[A-Z0-9]{6}$/.test(roomCode)) {
        return json({ error: "A valid 6-character roomCode is required." }, 400, origin);
      }
      const players = await getRoomPlayers(env.FIREBASE_DATABASE_URL, roomCode, user.idToken);
      const agoraUid = await makeAgoraUid(user.uid);
      if (!players.some((player) => player.uid === agoraUid)) {
        return json({ error: "You are not a member of this SCOTT room." }, 403, origin);
      }
      const expireAt = Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS;
      const token = RtcTokenBuilder.buildTokenWithUid(
        env.AGORA_APP_ID, env.AGORA_APP_CERTIFICATE, roomCode, agoraUid,
        RtcRole.PUBLISHER, TOKEN_TTL_SECONDS, TOKEN_TTL_SECONDS
      );
      return json({
        appId: env.AGORA_APP_ID, channel: roomCode, uid: agoraUid, token,
        expiresAt: expireAt, participants: players
      }, 200, origin);
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "Token request failed." }, 401, origin);
    }
  }
};
