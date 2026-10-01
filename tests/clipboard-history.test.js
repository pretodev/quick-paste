const assert = require("node:assert/strict")
const history = require("../ClipboardHistory.js")

const text = history.normalizeEntry({ type: "text", text: "hello", capturedAt: 42 })
assert.deepEqual(text, {
  type: "text", text: "hello", mime: "text/plain", capturedAt: 42,
  sourceAppId: "", sourceName: "", sourceIcon: ""
})
assert.equal(history.normalizeEntry({ type: "text", text: "" }), null)
assert.equal(history.normalizeEntry({ type: "unknown" }), null)
assert.equal(history.parseHistory("broken").length, 0)

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
