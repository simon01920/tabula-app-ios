// node --test worker/test/*.test.ts (Node ≥ 22.18 / 23.6 strips the types; no framework, no dependencies).
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash as nodeHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import worker, { ALPHABET, CODE_LENGTH, MAX_ENVELOPE_BYTES, TTL_SECONDS, handle, isEnvelope, newCode } from "../src/index.ts";
import type { Env } from "../src/index.ts";
import { SCRIPT, STYLE } from "../src/landing.ts";

type Put = { key: string; value: string; options: { expirationTtl: number } };

function fakeEnv(opts: { writeLimit?: number; readLimit?: number; teamID?: string; failPut?: boolean } = {}) {
  const store = new Map<string, string>();
  const puts: Put[] = [];
  const limiter = (max: number) => {
    const counts = new Map<string, number>();
    return {
      async limit({ key }: { key: string }) {
        counts.set(key, (counts.get(key) ?? 0) + 1);
        return { success: (counts.get(key) ?? 0) <= max };
      },
    };
  };
  const env: Env = {
    SHARES: {
      async get(key) {
        return store.get(key) ?? null;
      },
      async put(key, value, options) {
        if (opts.failPut) throw new Error("KV put failed: 429");
        puts.push({ key, value, options });
        store.set(key, value);
      },
    },
    RL_WRITE: limiter(opts.writeLimit ?? 1000),
    RL_READ: limiter(opts.readLimit ?? 1000),
    PUBLIC_ORIGIN: "https://tabula.simondev.sk",
    APPLE_TEAM_ID: opts.teamID ?? "",
    APP_BUNDLE_ID: "sk.simondev.tabula",
  };
  return { env, store, puts };
}

const ORIGIN = "https://tabula.simondev.sk";
const ENVELOPE = "1.q1YqU7JSMlTSUSpLzClNVbJSKkktLlGqBQA"; // shape only; the Worker never inflates
const post = (body: string, headers: Record<string, string> = {}, ip = "203.0.113.7") =>
  new Request(`${ORIGIN}/v1/share`, {
    method: "POST",
    body,
    headers: { "content-type": "application/json", "cf-connecting-ip": ip, ...headers },
  });
const get = (path: string, ip = "203.0.113.7") => new Request(`${ORIGIN}${path}`, { headers: { "cf-connecting-ip": ip } });
const share = (payload: unknown) => JSON.stringify({ v: 1, payload });

test("POST stores a valid envelope under a fresh code with a 30-day TTL; GET returns it", async () => {
  const { env, puts } = fakeEnv();
  const res = await handle(post(share(ENVELOPE)), env);
  assert.equal(res.status, 201);
  const body = (await res.json()) as { code: string; url: string; expiresAt: string };
  assert.match(body.code, new RegExp(`^[${ALPHABET}]{${CODE_LENGTH}}$`));
  assert.equal(body.url, `${ORIGIN}/c/${body.code}`);
  assert.ok(Math.abs(Date.parse(body.expiresAt) - (Date.now() + TTL_SECONDS * 1000)) < 5000);
  assert.deepEqual(puts, [{ key: body.code, value: ENVELOPE, options: { expirationTtl: 30 * 86400 } }]);
  assert.equal(res.headers.get("access-control-allow-origin"), null);

  const read = await handle(get(`/v1/share/${body.code}`), env);
  assert.equal(read.status, 200);
  assert.deepEqual(await read.json(), { v: 1, payload: ENVELOPE });
});

test("envelope validation matches SHARE_FORMAT §2 steps 1-5", () => {
  for (const ok of ["1.AA", "1.AAA", "1.AAAA", "1.-_Az09AA", "1.AQ", "1.AAE"]) assert.ok(isEnvelope(ok), ok);
  for (const bad of ["", "1.", "2.AAAA", "01.AAAA", "1AAAA", "1.A", "1.AAAAA", "1.AA==", "1.AB", "1.AAB", "1.A+/A", "1.AA AA", "1.ÄÄÄÄ"]) {
    assert.ok(!isEnvelope(bad), bad);
  }
});

test("POST rejects malformed bodies with 400 and stores nothing", async () => {
  const { env, puts } = fakeEnv();
  const bodies = [
    "not json",
    "null",
    "[]",
    '"1.AAAA"',
    JSON.stringify({ payload: ENVELOPE }),
    JSON.stringify({ v: 2, payload: ENVELOPE }),
    JSON.stringify({ v: "1", payload: ENVELOPE }),
    JSON.stringify({ v: 1, payload: ENVELOPE, extra: true }),
    share(42),
    share("2.AAAA"),
    share("1.AB"),
    share("1.<script>"),
  ];
  for (const body of bodies) assert.equal((await handle(post(body), env)).status, 400, body);
  assert.equal(puts.length, 0);
});

test("size cap: envelope at the §5.1 cap is accepted, one byte over is rejected, oversize bodies get 413", async () => {
  const { env } = fakeEnv();
  const atCap = "1." + "A".repeat(MAX_ENVELOPE_BYTES - 2);
  assert.equal((await handle(post(share(atCap)), env)).status, 201);
  assert.equal((await handle(post(share(atCap + "AAAA")), env)).status, 400);
  assert.equal((await handle(post(share("1." + "A".repeat(80_000))), env)).status, 413);
  assert.equal((await handle(post("{}", { "content-length": "999999" }), env)).status, 413);
  // A chunked body without Content-Length is capped while streaming.
  const stream = new ReadableStream({
    pull(c) {
      c.enqueue(new Uint8Array(32_768).fill(65));
    },
  });
  const chunked = new Request(`${ORIGIN}/v1/share`, {
    method: "POST",
    body: stream,
    headers: { "content-type": "application/json" },
    duplex: "half",
  } as RequestInit);
  assert.equal((await handle(chunked, env)).status, 413);
});

test("method and content-type checks; CORS stays closed", async () => {
  const { env } = fakeEnv();
  assert.equal((await handle(post(share(ENVELOPE), { "content-type": "text/plain" }), env)).status, 415);
  assert.equal((await handle(post(share(ENVELOPE), { "content-type": "application/x-www-form-urlencoded" }), env)).status, 415);
  assert.equal((await handle(post(share(ENVELOPE), { "content-type": "application/json; charset=UTF-8" }), env)).status, 201);
  const options = await handle(new Request(`${ORIGIN}/v1/share`, { method: "OPTIONS", headers: { origin: "https://evil.example" } }), env);
  assert.equal(options.status, 405);
  assert.equal(options.headers.get("access-control-allow-origin"), null);
  assert.equal((await handle(get("/v1/share"), env)).status, 405);
  assert.equal((await handle(new Request(`${ORIGIN}/v1/share/ABCDEFGH`, { method: "DELETE" }), env)).status, 405);
  assert.equal((await handle(new Request(`${ORIGIN}/t`, { method: "POST" }), env)).status, 405);
});

test("codes: CSPRNG output is canonical, rejection sampling skips bytes >= 248, collisions retry", async () => {
  for (let i = 0; i < 200; i++) assert.match(newCode(), new RegExp(`^[${ALPHABET}]{8}$`));
  // Bytes 248..255 are skipped; 0 -> '2', 30 -> 'Z', 31 -> '2'.
  const seq = [255, 248, 0, 30, 31, 1, 2, 3, 4, 5, 6];
  let i = 0;
  assert.equal(newCode((b) => b.forEach((_, j) => (b[j] = seq[i++ % seq.length]))), "2Z234567");

  const { env, store, puts } = fakeEnv();
  store.set("AAAAAAAA", "taken");
  store.set("BBBBBBBB", "taken");
  const codes = ["AAAAAAAA", "BBBBBBBB", "CCCCCCCC"];
  const res = await handle(post(share(ENVELOPE)), env, () => codes.shift()!);
  assert.equal(((await res.json()) as { code: string }).code, "CCCCCCCC");
  assert.equal(puts.length, 1);

  const always = await handle(post(share(ENVELOPE)), env, () => "AAAAAAAA");
  assert.equal(always.status, 503);
});

test("KV write failure (daily free-tier quota) returns 503", async () => {
  const { env } = fakeEnv({ failPut: true });
  assert.equal((await handle(post(share(ENVELOPE)), env)).status, 503);
});

test("rate limit: per IP, separate write and read limiters, 429 with Retry-After", async () => {
  const { env } = fakeEnv({ writeLimit: 2, readLimit: 3 });
  assert.equal((await handle(post(share(ENVELOPE)), env)).status, 201);
  assert.equal((await handle(post(share(ENVELOPE)), env)).status, 201);
  const limited = await handle(post(share(ENVELOPE)), env);
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "60");
  assert.equal((await handle(post(share(ENVELOPE), {}, "198.51.100.1"), env)).status, 201);
  for (let i = 0; i < 3; i++) assert.equal((await handle(get("/v1/share/22222222"), env)).status, 404);
  assert.equal((await handle(get("/v1/share/22222222"), env)).status, 429);
});

test("GET: unknown or non-canonical codes are 404", async () => {
  const { env, store } = fakeEnv();
  store.set("7KX2M9QH", ENVELOPE);
  for (const path of ["/v1/share/22222222", "/v1/share/7kx2m9qh", "/v1/share/7KX2-M9QH", "/v1/share/0OIL1234", "/v1/share/", "/v1/share/7KX2M9QH7", "/nope", "/c/7KX2M9Q0"]) {
    assert.equal((await handle(get(path), env)).status, 404, path);
  }
  assert.equal((await handle(get("/v1/share/7KX2M9QH"), env)).status, 200);
});

test("AASA: 404 until a Team ID is configured, then applinks for /t* and /c/*", async () => {
  assert.equal((await handle(get("/.well-known/apple-app-site-association"), fakeEnv().env)).status, 404);
  const res = await handle(get("/.well-known/apple-app-site-association"), fakeEnv({ teamID: "ABCDE12345" }).env);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "application/json");
  const body = (await res.json()) as { applinks: { details: { appIDs: string[]; components: { "/": string }[] }[] } };
  assert.deepEqual(body.applinks.details[0].appIDs, ["ABCDE12345.sk.simondev.tabula"]);
  assert.deepEqual(body.applinks.details[0].components.map((c) => c["/"]), ["/t*", "/c/*"]);
});

test("landing pages: app link carries the code, fragment script, strict CSP, no external URLs", async () => {
  const { env } = fakeEnv();
  const c = await handle(get("/c/7KX2M9QH"), env);
  assert.equal(c.status, 200);
  const html = await c.text();
  assert.match(html, /href="tabula:\/\/import\?code=7KX2M9QH"/);
  assert.match(html, /7KX2-M9QH/);
  assert.match(html, /<html lang="en">/);
  assert.doesNotMatch(html, /https?:\/\//); // no external requests or links
  const csp = c.headers.get("content-security-policy") ?? "";
  assert.match(csp, /default-src 'none'/);
  for (const inline of [STYLE, SCRIPT]) {
    const hash = createHash(inline);
    assert.ok(csp.includes(`'sha256-${hash}'`), "CSP hash must match the inline block");
  }
  const t = await handle(get("/t"), env);
  assert.equal(t.status, 200);
  assert.match(await t.text(), /href="tabula:\/\/import"/);
  assert.equal((await handle(get("/c/../../etc"), env)).status, 404);
});

test("no logging: handler never writes to the console and the source has no console calls", async () => {
  const calls: string[] = [];
  const methods = ["log", "info", "warn", "error", "debug", "trace"] as const;
  const saved = methods.map((m) => console[m]);
  methods.forEach((m) => (console[m] = (...a: unknown[]) => void calls.push(`${m}: ${a.join(" ")}`)));
  try {
    const { env } = fakeEnv({ failPut: true });
    await worker.fetch(post(share(ENVELOPE)), env);
    await worker.fetch(post("garbage"), env);
    await worker.fetch(get("/v1/share/22222222"), env);
  } finally {
    methods.forEach((m, i) => (console[m] = saved[i]));
  }
  assert.deepEqual(calls, []);
  const dir = new URL("../src/", import.meta.url);
  for (const file of readdirSync(dir)) assert.doesNotMatch(readFileSync(new URL(file, dir), "utf8"), /console\./, file);
});

function createHash(text: string): string {
  return nodeHash("sha256").update(text).digest("base64");
}
