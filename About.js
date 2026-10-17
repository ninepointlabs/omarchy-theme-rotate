// Facts and text for the About view (AboutView.qml), kept out of QML so node
// can check them (see tests/about.test.cjs), the same way SettingsMerge.js is.
//
// The version comes from manifest.json and the license from LICENSE at run
// time, so neither is copied here and neither can drift from the real file.

var NAME = "Theme Rotate"
var TAGLINE = "Randomize or auto-rotate your Omarchy theme, optionally following sunrise and sunset."
var ORGANIZATION = "Nine Point Labs"
var CREATED = "August 2026" // first commit: 2026-08-28
var SUPPORT_EMAIL = "help@ninepointlabs.com"

// Must stay true to what the plugin does. Network: only bin/sun-status.sh
// (curl to wttr.in). Commands: omarchy theme list/current/set, omarchy weather
// location. Files: shell.json (settings), the cache and state dirs below.
var PRIVACY = "No accounts and no telemetry. The only network request is to wttr.in, to look up "
  + "today's sunrise and sunset; it sends your Omarchy weather location if you have set one, "
  + "otherwise wttr.in estimates it from your IP address. The answer is cached for the day in "
  + "~/.cache/omarchy-theme-rotate. Themes are listed and applied with the omarchy command. "
  + "Settings stay in ~/.config/omarchy/shell.json and rotation state in "
  + "~/.local/state/omarchy-theme-rotate."

// "1.2.0" from manifest.json's text, or "" when it can't be read.
function manifestVersion(text) {
  try {
    var v = JSON.parse(String(text || "")).version
    return typeof v === "string" ? v : ""
  } catch (e) {
    return ""
  }
}

// "MIT License, © 2026 Nine Point Labs" from LICENSE's text: its first line
// plus its copyright line, as written there.
function licenseSummary(text) {
  var lines = String(text || "").split("\n")
  var name = ""
  var holder = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    if (name === "") name = line
    var m = /^Copyright\s+(?:\(c\)|©)\s*(.+)$/i.exec(line)
    if (m) { holder = "© " + m[1]; break }
  }
  return holder ? name + ", " + holder : name
}

// LICENSE with one line per paragraph, so it wraps to the panel's width.
function licenseBody(text) {
  var paras = String(text || "").replace(/\r/g, "").split(/\n\s*\n/)
  var out = []
  for (var i = 0; i < paras.length; i++) {
    var p = paras[i].split(/\s+/).join(" ").trim()
    if (p !== "") out.push(p)
  }
  return out.join("\n\n")
}

// bin/about-versions.sh prints "quickshell<TAB>qt<TAB>omarchy".
function parseVersions(text) {
  var parts = String(text || "").replace(/\n+$/, "").split("\n").pop().split("\t")
  return { quickshell: parts[0] || "", qt: parts[1] || "", omarchy: parts[2] || "" }
}

function builtWith(v) {
  var out = []
  if (v.quickshell) out.push("Quickshell " + v.quickshell)
  if (v.qt) out.push("Qt " + v.qt)
  if (v.omarchy) out.push("Omarchy " + v.omarchy)
  return out.length ? out.join(", ") : "Quickshell and Qt"
}

// Version details to paste into a support email.
function details(version, v, desktop) {
  return NAME + " " + (version || "unknown version") + "\n"
    + builtWith(v) + "\n"
    + (desktop || "unknown desktop")
}

function mailto(version, detailText) {
  return "mailto:" + SUPPORT_EMAIL
    + "?subject=" + encodeURIComponent(NAME + " " + (version || ""))
    + "&body=" + encodeURIComponent("\n\n--\n" + detailText)
}

if (typeof module !== "undefined") {
  module.exports = {
    NAME: NAME, TAGLINE: TAGLINE, ORGANIZATION: ORGANIZATION, CREATED: CREATED,
    SUPPORT_EMAIL: SUPPORT_EMAIL, PRIVACY: PRIVACY,
    manifestVersion: manifestVersion, licenseSummary: licenseSummary, licenseBody: licenseBody,
    parseVersions: parseVersions, builtWith: builtWith, details: details, mailto: mailto
  }
}
