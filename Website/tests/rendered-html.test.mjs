import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import test from "node:test";

const client = new URL("../dist/client/", import.meta.url);
const liveSite = "https://dmccullum.github.io/Granular/";

async function render(pathname = "/") {
  const { default: handler } = await import(new URL("../dist/server/index.js", import.meta.url).href);
  return handler(
    new Request(`http://localhost${pathname}`, { headers: { accept: "text/html" } }),
    {},
    { waitUntil() {}, passThroughOnException() {} },
  );
}

const html = await (async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  return response.text();
})();

// Visible text with tags stripped and entities decoded, so headings split across <span>s still match as phrases.
const text = html
  .replace(/<br\s*\/?>/g, " ")
  .replace(/<[^>]+>/g, "")
  .replace(/&nbsp;|\u00a0/g, " ")
  .replace(/&#x27;|&#39;/g, "'")
  .replace(/&amp;/g, "&");

const attributes = (tag, name) =>
  [...html.matchAll(new RegExp(`<${tag}\\b[^>]*>`, "g"))]
    .map(([element]) => element.match(new RegExp(`\\b${name}="([^"]*)"`))?.[1])
    .filter(Boolean);

// Maps a site URL like "/app-icon.png?v=11" to the file the static build serves for it.
function builtFile(url) {
  const path = new URL(url, "http://localhost/").pathname.replace(/^\//, "");
  return new URL(path, client);
}

function pngSize(url) {
  const bytes = readFileSync(builtFile(url));
  assert.equal(bytes.toString("ascii", 1, 4), "PNG", `${url} is a PNG`);
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

test("renders the landing page with its title and every section", () => {
  assert.match(html, /<title>Granular — [^<]+<\/title>/);
  assert.match(html, /<html lang="en"/);
  assert.match(html, /aria-label="Give your photos a film-like finish"/);
  for (const phrase of [
    "Drop photos in",
    "for instant results,",
    "or edit live.",
    "Tools for a film-like finish.",
    "See the results.",
    "Made with love by Daniel McCullum",
  ]) {
    assert.ok(text.includes(phrase), `page text includes "${phrase}"`);
  }
  for (const tool of ["FILM TONE", "VIGNETTE", "LENS BLUR", "DIFFUSION", "HALATION", "LANDSCAPE GLOW", "FILM GRAIN"]) {
    assert.match(html, new RegExp(`<h3>${tool}</h3>`));
  }
  assert.match(html, /type="range"/, "before-and-after slider is present");
  assert.equal(html.match(/class="comparison-thumb(?: [^"]*)?"/g)?.length, 3, "three comparison thumbnails");
});

test("every image in the page resolves to a built file", () => {
  const sources = attributes("img", "src");
  assert.ok(sources.length >= 8, `found ${sources.length} images`);
  for (const src of sources) {
    assert.ok(existsSync(builtFile(src)), `${src} exists in dist/client`);
  }
});

test("every image has alt text, and none repeats the word image, photo or picture", () => {
  for (const element of html.match(/<img\b[^>]*>/g)) {
    const alt = element.match(/\balt="([^"]*)"/)?.[1];
    assert.notEqual(alt, undefined, `${element} has an alt attribute`);
    assert.doesNotMatch(alt, /\b(image|photo|picture)\b/i, `alt "${alt}" is not redundant`);
  }
});

test("images loaded only after a click also exist in the build", () => {
  const chunks = new URL("_next/static/chunks/", client);
  const referenced = new Set();
  for (const name of readdirSync(chunks).filter((file) => file.endsWith(".js"))) {
    const source = readFileSync(new URL(name, chunks), "utf8");
    for (const [, path] of source.matchAll(/["'`]\/?([\w-]+\.(?:png|jpe?g|webp))(?:\?v=\d+)?["'`]/g)) referenced.add(path);
  }
  assert.ok(referenced.has("result-two-before.jpeg"), "comparison images are found in the client chunks");
  for (const path of referenced) assert.ok(existsSync(new URL(path, client)), `${path} exists in dist/client`);
});

test("links a 64 px favicon and a 180 px apple-touch-icon", () => {
  const icon = html.match(/<link rel="icon" href="([^"]+)"[^>]*type="image\/png"/)?.[1];
  const appleTouchIcon = html.match(/<link rel="apple-touch-icon" href="([^"]+)"/)?.[1];
  assert.ok(icon, "favicon link present");
  assert.ok(appleTouchIcon, "apple-touch-icon link present");
  assert.deepEqual(pngSize(icon), [64, 64]);
  assert.deepEqual(pngSize(appleTouchIcon), [180, 180]);
});

test("the header and closing icons use the same versioned app icon", () => {
  const icons = attributes("img", "src").filter((src) => src.includes("app-icon.png"));
  assert.equal(icons.length, 2, "header and closing icons");
  const [version] = icons[0].match(/\?v=\d+$/) ?? [];
  assert.ok(version, "app icon URL has a cache-busting version");
  assert.ok(icons.every((src) => src.endsWith(version)));
  assert.deepEqual(pngSize(icons[0]), [1024, 1024]);

});

test("share previews use the 1200 × 630 share card at an absolute URL, with one title and description", () => {
  // Share previews are fetched by other servers, so they need absolute URLs on the live site.
  const meta = (attr, key) => html.match(new RegExp(`<meta ${attr}="${key}" content="([^"]+)"`))?.[1];
  const ogImage = meta("property", "og:image");
  assert.match(ogImage, new RegExp(`^${liveSite.replace(/[.]/g, "\\.")}share-card\\.png\\?v=\\d+$`));
  assert.equal(meta("name", "twitter:image"), ogImage);
  assert.equal(meta("name", "twitter:card"), "summary_large_image");
  assert.deepEqual(pngSize(ogImage.slice(liveSite.length - 1)), [1200, 630]);
  const title = html.match(/<title>([^<]+)<\/title>/)[1];
  assert.equal(title, "Granular — A film finish for still images");
  assert.equal(meta("property", "og:title"), title);
  assert.equal(meta("name", "twitter:title"), title);
  const description = meta("name", "description");
  assert.equal(meta("property", "og:description"), description);
  assert.equal(meta("name", "twitter:description"), description);
});
