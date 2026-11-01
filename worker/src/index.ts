// Tabula share-code service (docs/specs/SHARING.md, SHARE_FORMAT.md §2/§5.1/§8, PHASE7_PLAN decisions 5–6).
// Privacy: no console output, no analytics, nothing stored but the envelope. Every request body is untrusted.
import { landingPage } from "./landing.ts";

// Must match TimetableCore ShortCode.alphabet / .length and ShareLimits.maxEnvelopeBytes.
export const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const CODE_LENGTH = 8;
export const MAX_ENVELOPE_BYTES = 65_536;
export const MAX_BODY_BYTES = MAX_ENVELOPE_BYTES + 256; // room for {"v":1,"payload":"…"} and whitespace
export const TTL_SECONDS = 30 * 24 * 60 * 60;
const MAX_ATTEMPTS = 5;
const CODE_RE = new RegExp(`^[${ALPHABET}]{${CODE_LENGTH}}$`);
const B64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

export interface KV {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options: { expirationTtl: number }): Promise<void>;
}
export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}
export interface Env {
  SHARES: KV;
  RL_WRITE: RateLimiter;
  RL_READ: RateLimiter;
  PUBLIC_ORIGIN: string;
  APPLE_TEAM_ID: string;
  APP_BUNDLE_ID: string;
}

/** A uniform code from a CSPRNG: bytes ≥ 248 (= 8 × 31) are rejected, so there is no modulo bias. */
export function newCode(fill: (bytes: Uint8Array) => void = (b) => crypto.getRandomValues(b)): string {
  const buf = new Uint8Array(16);
  let code = "";
  while (code.length < CODE_LENGTH) {
    fill(buf);
    for (const b of buf) if (b < 248 && code.length < CODE_LENGTH) code += ALPHABET[b % 31];
  }
  return code;
}

/** SHARE_FORMAT §2 steps 1–5 for version 1: `"1."` + canonical base64url (no `=`, len ≢ 1 mod 4, zero pad bits). */
export function isEnvelope(s: string): boolean {
  if (s.length > MAX_ENVELOPE_BYTES || !s.startsWith("1.")) return false;
  const body = s.slice(2);
  if (!/^[A-Za-z0-9_-]+$/.test(body) || body.length % 4 === 1) return false; // ASCII only, so length = bytes
  const rem = body.length % 4;
  return rem === 0 || (B64URL.indexOf(body[body.length - 1]) & (rem === 2 ? 0x0f : 0x03)) === 0;
}

const SECURITY_HEADERS = { "x-content-type-options": "nosniff", "referrer-policy": "no-referrer" };

function json(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...SECURITY_HEADERS, ...extra },
  });
}
const error = (status: number, code: string, extra: Record<string, string> = {}) => json(status, { error: code }, extra);
const notFound = () => error(404, "not_found");
const methodNotAllowed = (allow: string) => error(405, "method_not_allowed", { allow });
const tooMany = () => error(429, "rate_limited", { "retry-after": "60" });

// Used only as an ephemeral rate-limit key; never stored or logged.
const clientKey = (req: Request) => req.headers.get("cf-connecting-ip") ?? "unknown";

/** Reads at most `max` bytes (chunked bodies too); `null` when larger. */
async function readCapped(req: Request, max: number): Promise<string | null> {
  if (Number(req.headers.get("content-length") ?? 0) > max) return null;
  if (!req.body) return "";
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const all = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    all.set(c, offset);
    offset += c.byteLength;
  }
  return new TextDecoder().decode(all); // invalid UTF-8 becomes U+FFFD and fails isEnvelope
}

async function createShare(req: Request, env: Env, makeCode: () => string): Promise<Response> {
  if (!(await env.RL_WRITE.limit({ key: clientKey(req) })).success) return tooMany();
  const type = (req.headers.get("content-type") ?? "").trim().toLowerCase();
  if (type !== "application/json" && type !== "application/json; charset=utf-8") return error(415, "unsupported_media_type");
  const text = await readCapped(req, MAX_BODY_BYTES);
  if (text === null) return error(413, "payload_too_large");
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return error(400, "invalid_json");
  }
  // Strict schema: exactly {"v": 1, "payload": <envelope>}.
  if (typeof body !== "object" || body === null || Array.isArray(body)) return error(400, "invalid_body");
  const record = body as Record<string, unknown>;
  if (Object.keys(record).sort().join() !== "payload,v" || record.v !== 1) return error(400, "invalid_body");
  if (typeof record.payload !== "string" || !isEnvelope(record.payload)) return error(400, "invalid_envelope");
  try {
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const code = makeCode();
      // shortcut: KV has no put-if-absent; two concurrent writers drawing the same code (p ≈ 31⁻⁸) is accepted.
      if ((await env.SHARES.get(code)) !== null) continue;
      await env.SHARES.put(code, record.payload, { expirationTtl: TTL_SECONDS });
      const expiresAt = new Date(Date.now() + TTL_SECONDS * 1000).toISOString();
      return json(201, { code, url: `${env.PUBLIC_ORIGIN}/c/${code}`, expiresAt });
    }
    return error(503, "unavailable");
  } catch {
    return error(503, "unavailable"); // e.g. the free-tier daily KV write quota is used up (resets 00:00 UTC)
  }
}

async function readShare(req: Request, env: Env, code: string): Promise<Response> {
  if (!(await env.RL_READ.limit({ key: clientKey(req) })).success) return tooMany();
  if (!CODE_RE.test(code)) return notFound();
  try {
    const payload = await env.SHARES.get(code);
    return payload === null ? notFound() : json(200, { v: 1, payload });
  } catch {
    return error(503, "unavailable");
  }
}

function aasa(env: Env): Response {
  // Not served until a real Team ID is configured, so Apple's CDN never caches a placeholder file.
  if (!/^[A-Z0-9]{10}$/.test(env.APPLE_TEAM_ID ?? "")) return notFound();
  const body = {
    applinks: {
      details: [
        {
          appIDs: [`${env.APPLE_TEAM_ID}.${env.APP_BUNDLE_ID}`],
          components: [
            { "/": "/t*", comment: "Inline share link; the payload is in the fragment" },
            { "/": "/c/*", comment: "Short-code share link" },
          ],
        },
      ],
    },
  };
  return new Response(JSON.stringify(body), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=3600", ...SECURITY_HEADERS },
  });
}

export async function handle(req: Request, env: Env, makeCode: () => string = newCode): Promise<Response> {
  const path = new URL(req.url).pathname;
  if (path === "/v1/share") return req.method === "POST" ? createShare(req, env, makeCode) : methodNotAllowed("POST");
  const api = /^\/v1\/share\/([^/]*)$/.exec(path);
  if (api) return req.method === "GET" ? readShare(req, env, api[1]) : methodNotAllowed("GET");
  if (req.method !== "GET" && req.method !== "HEAD") return methodNotAllowed("GET, HEAD");
  if (path === "/.well-known/apple-app-site-association") return aasa(env);
  if (path === "/t") return landingPage(null);
  const landing = /^\/c\/([^/]+)$/.exec(path);
  if (landing && CODE_RE.test(landing[1])) return landingPage(landing[1]);
  return notFound();
}

export default { fetch: (req: Request, env: Env) => handle(req, env) };
