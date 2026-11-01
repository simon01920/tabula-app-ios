// Static landing page for people who open a share link in a browser. No trackers, no external requests.
// The inline payload stays in the fragment (never sent to the server); the script copies it into the app link.

export const STYLE = `
:root { color-scheme: light dark; --bg: #fbfaf6; --fg: #1c1b19; --muted: #55524b; --accent: #1f4fd1; --on-accent: #ffffff; }
@media (prefers-color-scheme: dark) { :root { --bg: #151514; --fg: #f2f0ea; --muted: #b9b5ab; --accent: #8fb0ff; --on-accent: #0d1a3d; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 1.0625rem/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
main { max-width: 34rem; margin: 0 auto; padding: 3rem 1rem; }
h1 { font-size: 1.75rem; line-height: 1.2; margin: 0 0 1rem; }
p { margin: 0 0 1rem; }
.button { display: inline-block; min-height: 44px; padding: 0.75rem 1.5rem; border-radius: 0.75rem; background: var(--accent); color: var(--on-accent); font-weight: 600; text-decoration: none; }
.button:focus-visible { outline: 3px solid var(--fg); outline-offset: 3px; }
.code { font: 600 1.25rem ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: 0.08em; }
.small { color: var(--muted); font-size: 0.9375rem; }
`;

export const SCRIPT = `(function () {
  var h = location.hash;
  if (location.pathname === "/t" && /^#[A-Za-z0-9._-]+$/.test(h)) document.getElementById("open").href = "tabula://import" + h;
})();`;

async function sha256(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return `'sha256-${btoa(String.fromCharCode(...digest))}'`;
}

let csp: Promise<string> | undefined;
const contentSecurityPolicy = () =>
  (csp ??= Promise.all([sha256(STYLE), sha256(SCRIPT)]).then(
    ([style, script]) =>
      `default-src 'none'; style-src ${style}; script-src ${script}; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
  ));

/** `code` is a canonical short code (validated by the caller: alphabet characters only) or null for `/t`. */
export async function landingPage(code: string | null): Promise<Response> {
  const href = code ? `tabula://import?code=${code}` : "tabula://import";
  const codeLine = code
    ? `<p>Or enter this code in Tabula: <strong class="code">${code.slice(0, 4)}-${code.slice(4)}</strong></p>`
    : "";
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="robots" content="noindex">
<title>Open in Tabula</title>
<style>${STYLE}</style>
</head>
<body>
<main>
<h1>A timetable was shared with you</h1>
<p>Open it in Tabula. You will see a preview before anything is imported.</p>
<p><a id="open" class="button" href="${href}">Open in Tabula</a></p>
${codeLine}
<p>Don't have Tabula yet? It is coming to the App Store soon.</p>
<p class="small">Share links expire after 30 days. This page sets no cookies and loads nothing from other sites.</p>
</main>
<script>${SCRIPT}</script>
</body>
</html>
`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
      "content-security-policy": await contentSecurityPolicy(),
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
    },
  });
}
