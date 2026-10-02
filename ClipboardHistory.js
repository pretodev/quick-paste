function stringValue(value) {
  return value === undefined || value === null ? "" : String(value)
}

function normalizeEntry(value) {
  if (typeof value === "string") value = { type: "text", text: value }
  if (!value || typeof value !== "object") return null

  var type = stringValue(value.type || value.kind)
  var entry
  if (type === "text") {
    var text = stringValue(value.text)
    if (!text.length) return null
    entry = { type: "text", text: text, mime: "text/plain" }
  } else if (type === "image") {
    var path = stringValue(value.path)
    if (!path.length) return null
    entry = {
      type: "image",
      path: path,
      mime: stringValue(value.mime || "image/png")
    }
  } else {
    return null
  }

  var formats = []
  if (Array.isArray(value.formats)) {
    for (var i = 0; i < value.formats.length; i++) {
      var format = value.formats[i]
      if (!format || typeof format !== "object") continue
      var formatMime = stringValue(format.mime)
      var formatPath = stringValue(format.path)
      if (formatMime.length && formatPath.length)
        formats.push({ mime: formatMime, path: formatPath })
    }
  }
  if (formats.length) entry.formats = formats
  var bundleId = stringValue(value.bundleId)
  if (bundleId.length) entry.bundleId = bundleId

  if (entry.type === "text" && value.linkPreview && typeof value.linkPreview === "object") {
    var description = stringValue(value.linkPreview.description)
    var image = stringValue(value.linkPreview.image)
    var url = stringValue(value.linkPreview.url)
    if (description.length || image.length || url.length) {
      entry.linkPreview = { description: description, image: image, url: url }
    }
  }

  var capturedAt = Number(value.capturedAtMs !== undefined ? value.capturedAtMs : value.capturedAt)
  entry.capturedAt = isFinite(capturedAt) && capturedAt > 0 ? capturedAt : 0
  entry.sourceAppId = stringValue(value.sourceAppId)
  entry.sourceName = stringValue(value.sourceName)
  entry.sourceIcon = stringValue(value.sourceIcon)
  return entry
}

function entryKey(entry) {
  var value = normalizeEntry(entry)
  if (!value) return ""
  if (value.bundleId) return "bundle:" + value.bundleId
  return value.type === "image" ? "image:" + value.path : "text:" + value.text
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(stringValue(raw || "[]"))
    if (!Array.isArray(parsed)) return []
    var result = []
    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) result.push(entry)
    }
    return result
  } catch (error) {
    return []
  }
}

function addEntry(history, candidate, limit) {
  var entry = normalizeEntry(candidate)
  var max = Math.max(0, Number(limit) || 0)
  if (!entry || max === 0) return []

  var key = entryKey(entry)
  var values = Array.isArray(history) ? history : []
  var result = [entry]
  for (var i = 0; i < values.length && result.length < max; i++) {
    var existing = normalizeEntry(values[i])
    if (existing && entryKey(existing) !== key) result.push(existing)
  }
  return result
}

function removeEntry(history, index) {
  var values = Array.isArray(history) ? history : []
  var position = Number(index)
  if (!isFinite(position) || Math.floor(position) !== position
      || position < 0 || position >= values.length) return values.slice()
  return values.slice(0, position).concat(values.slice(position + 1))
}

function importLegacy(history, legacy, limit) {
  var max = Math.max(0, Number(limit) || 0)
  var result = []
  var seen = {}
  var sources = [Array.isArray(history) ? history : [], Array.isArray(legacy) ? legacy : []]
  for (var s = 0; s < sources.length; s++) {
    for (var i = 0; i < sources[s].length && result.length < max; i++) {
      var entry = normalizeEntry(sources[s][i])
      var key = entryKey(entry)
      if (!entry || seen[key]) continue
      seen[key] = true
      result.push(entry)
    }
  }
  return result
}

function characterCount(text) {
  var value = stringValue(text)
  var count = 0
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length) {
      var next = value.charCodeAt(i + 1)
      if (next >= 0xDC00 && next <= 0xDFFF) i++
    }
    count++
  }
  return count
}

function relativeTime(timestamp, now) {
  var value = Number(timestamp)
  if (!isFinite(value) || value <= 0) return "tempo desconhecido"
  var delta = Math.max(0, Math.floor((Number(now || Date.now()) - value) / 1000))
  if (delta < 10) return "agora"
  if (delta < 60) return "há " + delta + " segundos"
  var minutes = Math.floor(delta / 60)
  if (minutes < 60) return "há " + minutes + (minutes === 1 ? " minuto" : " minutos")
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return "há " + hours + (hours === 1 ? " hora" : " horas")
  var days = Math.floor(hours / 24)
  return "há " + days + (days === 1 ? " dia" : " dias")
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeEntry: normalizeEntry,
    entryKey: entryKey,
    parseHistory: parseHistory,
    addEntry: addEntry,
    removeEntry: removeEntry,
    importLegacy: importLegacy,
    characterCount: characterCount,
    relativeTime: relativeTime
  }
}
