const assert = require("node:assert/strict")
const i18n = require("../I18n.js")

for (const locale of ["en_US", "pt_BR", "es_ES"]) {
  const language = i18n.language(locale)
  assert.equal(language, locale.slice(0, 2))
  assert.deepEqual(Object.keys(i18n.strings[language]).sort(), Object.keys(i18n.strings.en).sort())
  assert.equal(i18n.count(locale, "itemOne", "itemMany", 1).includes("1"), true)
  assert.equal(i18n.count(locale, "itemOne", "itemMany", 2).includes("2"), true)
  assert.equal(i18n.relativeTime(locale, 0, 1000), i18n.tr(locale, "unknownTime"))
  assert.equal(i18n.relativeTime(locale, 99000, 100000), i18n.tr(locale, "now"))
  assert.equal(i18n.relativeTime(locale, 40000, 100000), i18n.tr(locale, "oneMinuteAgo"))
  assert.equal(i18n.relativeTime(locale, 100000, 7300000), i18n.tr(locale, "hoursAgo", { count: 2 }))
}

assert.equal(i18n.language("fr_FR"), "en")
assert.equal(i18n.language("pt-BR.UTF-8"), "pt")
assert.equal(i18n.tr("es_ES", "pasteIn", { app: "Firefox" }), "Pegar en Firefox")
assert.equal(i18n.tr("pt_BR", "andMore", { name: "foto.png", count: 2 }), "foto.png e mais 2")
assert.equal(i18n.count("en_US", "characterOne", "characterMany", 1), "1 character")
assert.equal(i18n.count("en_US", "characterOne", "characterMany", 2), "2 characters")

console.log("i18n tests passed")
