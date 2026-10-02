// UI copy stays separate from clipboard data so changing languages never rewrites history.
var strings = {
  en: {
    clipboard: "Clipboard",
    search: "Search history",
    unknownApp: "Unknown application",
    file: "File",
    files: "Files",
    image: "Image",
    link: "Link",
    text: "Text",
    deleteHistory: "Remove from history",
    noResults: "No results found",
    empty: "Clipboard is empty",
    openLink: "Open link in browser",
    openFile: "Open file",
    openFiles: "Open files",
    revealFile: "Show file in Files",
    revealFiles: "Show files in Files",
    pasteAbsolute: "Paste absolute path",
    pasteHome: "Paste path with ~/",
    tensakuBusy: "Tensaku is already open",
    openTensaku: "Open in Tensaku",
    pasteIn: "Paste into {app}",
    noApp: "no application",
    pastePlain: "Paste without formatting",
    andMore: "{name} and {count} more",
    unknownTime: "unknown time",
    now: "now",
    secondsAgo: "{count} seconds ago",
    oneMinuteAgo: "1 minute ago",
    minutesAgo: "{count} minutes ago",
    oneHourAgo: "1 hour ago",
    hoursAgo: "{count} hours ago",
    oneDayAgo: "1 day ago",
    daysAgo: "{count} days ago",
    itemOne: "{count} item",
    itemMany: "{count} items",
    fileOrFolderOne: "{count} file or folder",
    fileOrFolderMany: "{count} files or folders",
    characterOne: "{count} character",
    characterMany: "{count} characters"
  },
  pt: {
    clipboard: "Área de transferência",
    search: "Buscar no histórico",
    unknownApp: "Aplicativo desconhecido",
    file: "Arquivo",
    files: "Arquivos",
    image: "Imagem",
    link: "Link",
    text: "Texto",
    deleteHistory: "Excluir do histórico",
    noResults: "Nenhum resultado encontrado",
    empty: "A área de transferência está vazia",
    openLink: "Abrir link no navegador",
    openFile: "Abrir arquivo",
    openFiles: "Abrir arquivos",
    revealFile: "Abrir local do arquivo",
    revealFiles: "Abrir local dos arquivos",
    pasteAbsolute: "Colar caminho absoluto",
    pasteHome: "Colar caminho com ~/",
    tensakuBusy: "Tensaku já está aberto",
    openTensaku: "Abrir no Tensaku",
    pasteIn: "Colar em {app}",
    noApp: "nenhum aplicativo",
    pastePlain: "Colar sem formatação",
    andMore: "{name} e mais {count}",
    unknownTime: "tempo desconhecido",
    now: "agora",
    secondsAgo: "há {count} segundos",
    oneMinuteAgo: "há 1 minuto",
    minutesAgo: "há {count} minutos",
    oneHourAgo: "há 1 hora",
    hoursAgo: "há {count} horas",
    oneDayAgo: "há 1 dia",
    daysAgo: "há {count} dias",
    itemOne: "{count} item",
    itemMany: "{count} itens",
    fileOrFolderOne: "{count} arquivo ou pasta",
    fileOrFolderMany: "{count} arquivos ou pastas",
    characterOne: "{count} caractere",
    characterMany: "{count} caracteres"
  },
  es: {
    clipboard: "Portapapeles",
    search: "Buscar en el historial",
    unknownApp: "Aplicación desconocida",
    file: "Archivo",
    files: "Archivos",
    image: "Imagen",
    link: "Enlace",
    text: "Texto",
    deleteHistory: "Eliminar del historial",
    noResults: "No se encontraron resultados",
    empty: "El portapapeles está vacío",
    openLink: "Abrir enlace en el navegador",
    openFile: "Abrir archivo",
    openFiles: "Abrir archivos",
    revealFile: "Mostrar archivo en Archivos",
    revealFiles: "Mostrar archivos en Archivos",
    pasteAbsolute: "Pegar ruta absoluta",
    pasteHome: "Pegar ruta con ~/",
    tensakuBusy: "Tensaku ya está abierto",
    openTensaku: "Abrir en Tensaku",
    pasteIn: "Pegar en {app}",
    noApp: "ninguna aplicación",
    pastePlain: "Pegar sin formato",
    andMore: "{name} y {count} más",
    unknownTime: "hora desconocida",
    now: "ahora",
    secondsAgo: "hace {count} segundos",
    oneMinuteAgo: "hace 1 minuto",
    minutesAgo: "hace {count} minutos",
    oneHourAgo: "hace 1 hora",
    hoursAgo: "hace {count} horas",
    oneDayAgo: "hace 1 día",
    daysAgo: "hace {count} días",
    itemOne: "{count} elemento",
    itemMany: "{count} elementos",
    fileOrFolderOne: "{count} archivo o carpeta",
    fileOrFolderMany: "{count} archivos o carpetas",
    characterOne: "{count} carácter",
    characterMany: "{count} caracteres"
  }
}

function language(localeName) {
  var code = String(localeName || "").split(/[_.@-]/)[0].toLowerCase()
  return strings[code] ? code : "en"
}

function tr(localeName, key, values) {
  var lang = language(localeName)
  var template = strings[lang][key] || strings.en[key] || key
  return template.replace(/\{([a-z]+)\}/g, function(match, name) {
    return values && values[name] !== undefined ? String(values[name]) : match
  })
}

function count(localeName, oneKey, manyKey, value) {
  return tr(localeName, value === 1 ? oneKey : manyKey, { count: value })
}

function relativeTime(localeName, timestamp, now) {
  var value = Number(timestamp)
  if (!isFinite(value) || value <= 0) return tr(localeName, "unknownTime")
  var delta = Math.max(0, Math.floor((Number(now || Date.now()) - value) / 1000))
  if (delta < 10) return tr(localeName, "now")
  if (delta < 60) return tr(localeName, "secondsAgo", { count: delta })
  var minutes = Math.floor(delta / 60)
  if (minutes < 60) return count(localeName, "oneMinuteAgo", "minutesAgo", minutes)
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return count(localeName, "oneHourAgo", "hoursAgo", hours)
  var days = Math.floor(hours / 24)
  return count(localeName, "oneDayAgo", "daysAgo", days)
}

if (typeof module !== "undefined")
  module.exports = { strings: strings, language: language, tr: tr, count: count, relativeTime: relativeTime }
