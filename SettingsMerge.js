// Settings merge rules for the Theme Rotate widget, kept out of Panel.qml so
// they can be exercised directly (see tests/settings-merge.test.cjs) instead
// of only through a running shell.
//
// The problem these rules solve: the shell injects a `settings` snapshot into
// each widget instance, and there is one instance per monitor plus whatever a
// plugin hot-reload leaves running. Any of them can persist at any time, and
// an instance that merges its change onto its own snapshot will write back
// whatever that snapshot still says about every other key — quietly undoing
// another instance's change. The widget therefore treats ~/.config/omarchy/
// shell.json as the source of truth and merges onto that, while still
// carrying over keys only the snapshot knows about.
//
// Pure JS, no QML or Qt types, so node can require it the same way the other
// plugins here keep their Model.js testable — see tests/settings-merge.test.cjs.

// This widget's entry in a shell.json document, or null when the text isn't
// parseable or the widget isn't in the layout. Entries live in the bar
// layout, except for non-widget plugins, which live in `plugins`.
function entryFromConfig(text, moduleName) {
  var raw = String(text || "")
  if (raw.trim() === "") return null
  var config
  try {
    config = JSON.parse(raw)
  } catch (e) {
    return null
  }
  if (!config || typeof config !== "object") return null

  var id = String(moduleName || "")
  var sections = ["left", "center", "right"]
  var layout = config.bar && config.bar.layout ? config.bar.layout : null
  for (var s = 0; s < sections.length; s++) {
    var arr = layout ? layout[sections[s]] : null
    if (!arr || typeof arr.length !== "number") continue
    for (var i = 0; i < arr.length; i++)
      if (arr[i] && String(arr[i].id) === id) return arr[i]
  }
  var plugins = config.plugins
  if (plugins && typeof plugins.length === "number")
    for (var j = 0; j < plugins.length; j++)
      if (plugins[j] && String(plugins[j].id) === id) return plugins[j]
  return null
}

// The entry to persist: the union of both bases with the live entry winning
// on conflict, then the caller's overrides.
//
// Union rather than "live entry only" because the two can disagree in the
// moment between another instance's write and this instance's file watcher
// seeing it, and in that window each side may hold a key the other lacks.
// This widget never deletes a key, so keeping every key either side knows
// about — while preferring the fresher value — makes a lost setting
// impossible from either direction.
function mergeEntry(moduleName, snapshot, live, overrides) {
  var entry = { id: String(moduleName || "") }
  var sources = [snapshot || {}, live || {}, overrides || {}]
  for (var i = 0; i < sources.length; i++)
    for (var key in sources[i])
      if (key !== "id") entry[key] = sources[i][key]
  return entry
}

// One setting, live entry first and the injected snapshot as the fallback for
// keys it doesn't carry. `false` and `0` are values, not misses — only
// undefined and null fall through to the next source.
function settingValue(live, snapshot, name, fallback) {
  var value = live ? live[name] : undefined
  if (value === undefined || value === null)
    value = snapshot ? snapshot[name] : undefined
  return value === undefined || value === null ? fallback : value
}

// Overrides queued while the live config hasn't been read yet. Later values
// win, so the queue always describes the caller's latest intent.
function mergeOverrides(queued, overrides) {
  var out = ({})
  var sources = [queued || {}, overrides || {}]
  for (var i = 0; i < sources.length; i++)
    for (var key in sources[i]) out[key] = sources[i][key]
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    entryFromConfig: entryFromConfig, mergeEntry: mergeEntry,
    settingValue: settingValue, mergeOverrides: mergeOverrides
  }
}
