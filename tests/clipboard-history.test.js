const assert = require("node:assert/strict")
const history = require("../ui/ClipboardHistory.js")

const text = history.normalizeEntry({ type: "text", text: "hello", capturedAt: 42 })
assert.deepEqual(text, {
  type: "text", text: "hello", mime: "text/plain", capturedAt: 42,
  sourceAppId: "", sourceName: "", sourceIcon: ""
})
assert.equal(history.normalizeEntry({ type: "text", text: "" }), null)
assert.equal(history.normalizeEntry({ type: "unknown" }), null)
assert.equal(history.parseHistory("broken").length, 0)

const rich = history.normalizeEntry({
  type: "text", text: "hello", bundleId: "abc",
  formats: [
    { mime: "text/plain", path: "/state/plain" },
    { mime: "text/html", path: "/state/html" },
    { mime: "", path: "/ignored" }
  ]
})
assert.equal(rich.bundleId, "abc")
assert.deepEqual(rich.formats, [
  { mime: "text/plain", path: "/state/plain" },
  { mime: "text/html", path: "/state/html" }
])
assert.equal(history.entryKey(rich), "bundle:abc")

const files = history.normalizeEntry({
  type: "file", paths: ["/home/user/Olá mundo.txt", "/tmp/photo.png"], bundleId: "files",
  formats: [{ mime: "text/uri-list", path: "/state/uri-list" }]
})
assert.deepEqual(files.paths, ["/home/user/Olá mundo.txt", "/tmp/photo.png"])
assert.equal(history.entryKey(files), "bundle:files")
assert.equal(history.normalizeEntry({ type: "file", paths: [] }), null)
assert.equal(history.normalizeEntry({ type: "file", paths: ["relative"] }), null)
assert.equal(history.parseHistory(JSON.stringify([files]))[0].type, "file")
const grouped = history.addEntry([], files, 300)
assert.equal(grouped.length, 1)
assert.deepEqual(grouped[0].paths, files.paths)
const folder = history.normalizeEntry({ type: "file", paths: ["/home/user/Documents"], isDirectory: true })
assert.equal(folder.isDirectory, true)
assert.equal(history.parseHistory(JSON.stringify([folder]))[0].isDirectory, true)
assert.equal(history.normalizeEntry({ type: "file", paths: files.paths, isDirectory: true }).isDirectory, undefined)

const link = history.normalizeEntry({
  type: "text",
  text: "https://example.com/original",
  linkPreview: {
    description: "An example",
    image: "https://example.com/card.png",
    url: "https://example.com/canonical"
  }
})
assert.deepEqual(link.linkPreview, {
  description: "An example",
  image: "https://example.com/card.png",
  url: "https://example.com/canonical"
})
assert.equal(history.normalizeEntry({
  type: "text", text: "https://example.com", linkPreview: {}
}).linkPreview, undefined)
assert.equal(history.webUrl("https://example.com/path?q=1"), "https://example.com/path?q=1")
assert.equal(history.webUrl("HTTP://example.com"), "HTTP://example.com")
assert.equal(history.webUrl("https://"), "")
assert.equal(history.webUrl("https://example.com trailing"), "")
assert.equal(history.webUrl("example.com"), "")
assert.equal(history.webUrl(link.linkPreview.url), "https://example.com/canonical")

const original = [
  { type: "text", text: "older", capturedAt: 1 },
  { type: "text", text: "same", capturedAt: 2 }
]
const deduplicated = history.addEntry(original, {
  type: "text", text: "same", capturedAt: 3, sourceName: "Code"
}, 300)
assert.equal(deduplicated.length, 2)
assert.equal(deduplicated[0].text, "same")
assert.equal(deduplicated[0].capturedAt, 3)
assert.equal(deduplicated[0].sourceName, "Code")

const limited = history.addEntry(original, { type: "text", text: "new" }, 2)
assert.deepEqual(limited.map(entry => entry.text), ["new", "older"])

const removed = history.removeEntry(original, 0)
assert.deepEqual(removed.map(entry => entry.text), ["same"])
assert.notEqual(removed, original)
assert.deepEqual(history.removeEntry(original, -1), original)
assert.deepEqual(history.removeEntry(original, 99), original)

assert.equal(history.matchesSearch({ type: "text", text: "Olá Mundo\nsegunda linha" }, "MUNDO"), true)
assert.equal(history.matchesSearch({ type: "text", text: "Olá Mundo" }, "ausente"), false)
assert.equal(history.matchesSearch(link, "CANONICAL"), true)
assert.equal(history.matchesSearch(link, "an EXAMPLE"), true)
assert.equal(history.matchesSearch(files, "OLÁ MUNDO.TXT"), true)
assert.equal(history.matchesSearch(files, "/home/user"), false)
assert.equal(history.matchesSearch({ type: "image", path: "/tmp/photo.png" }, "photo"), false)
assert.equal(history.matchesSearch({ type: "image", path: "/tmp/photo.png" }, " "), true)
assert.equal(history.matchesSearch(null, "test"), false)

const imported = history.importLegacy(
  [{ type: "text", text: "owned", sourceName: "Terminal" }],
  [{ type: "text", text: "owned" }, { type: "image", path: "/tmp/a.png" }],
  300
)
assert.equal(imported.length, 2)
assert.equal(imported[0].sourceName, "Terminal")
assert.equal(imported[1].type, "image")
assert.equal(imported[1].capturedAt, 0)

assert.equal(history.characterCount("a😀b"), 3)
assert.equal(history.relativeTime(0, 1000), "tempo desconhecido")
assert.equal(history.relativeTime(99000, 100000), "agora")
assert.equal(history.relativeTime(40000, 100000), "há 1 minuto")
assert.equal(history.relativeTime(100000, 7300000), "há 2 horas")

console.log("clipboard history tests passed")
