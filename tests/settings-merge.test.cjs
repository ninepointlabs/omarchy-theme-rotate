// Node test runner (`node --test tests/settings-merge.test.cjs`) for the
// settings merge rules the widget persists through.
//
// These rules exist because several instances of the widget are alive at once
// (one per monitor, plus whatever a plugin hot-reload leaves running) and each
// holds its own injected `settings` snapshot. The cases below pin down the one
// property that matters: a write can update keys, but it can never lose one
// that either the live shell.json entry or the instance's own snapshot knows
// about. A running shell can't be made to hold the two out of sync on demand,
// which is exactly why this lives here instead of in a system test.
const test = require("node:test")
const assert = require("node:assert/strict")
const Merge = require("../SettingsMerge.js")

const ID = "tim.theme-rotate"

function config(entry, section) {
  return JSON.stringify({
    version: 1,
    bar: {
      layout: {
        left: [{ id: "omarchy.menu" }],
        center: [],
        right: [{ id: "omarchy.tray" }],
        [section || "right"]: [{ id: "omarchy.tray" }, entry]
      }
    }
  })
}

test("entryFromConfig finds the widget's entry in any bar section", () => {
  for (const section of ["left", "center", "right"]) {
    const text = config({ id: ID, mode: "interval", intervalHours: 6 }, section)
    assert.deepEqual(Merge.entryFromConfig(text, ID), { id: ID, mode: "interval", intervalHours: 6 })
  }
})

test("entryFromConfig falls back to the top-level plugins list", () => {
  const text = JSON.stringify({ version: 1, plugins: [{ id: "other" }, { id: ID, paused: true }] })
  assert.deepEqual(Merge.entryFromConfig(text, ID), { id: ID, paused: true })
})

test("entryFromConfig returns null rather than guessing", () => {
  assert.equal(Merge.entryFromConfig("", ID), null)
  assert.equal(Merge.entryFromConfig("   ", ID), null)
  assert.equal(Merge.entryFromConfig("{not json", ID), null)
  assert.equal(Merge.entryFromConfig("[]", ID), null)
  assert.equal(Merge.entryFromConfig(JSON.stringify({ version: 1 }), ID), null)
  assert.equal(Merge.entryFromConfig(config({ id: "someone.else" }), ID), null)
})

test("mergeEntry keeps the widget id and applies overrides last", () => {
  const entry = Merge.mergeEntry(ID, { id: "stale.id", mode: "off" }, { id: ID, mode: "interval" }, { mode: "off" })
  assert.equal(entry.id, ID)
  assert.equal(entry.mode, "off")
})

test("mergeEntry prefers the live entry over a stale snapshot", () => {
  // Another instance moved the schedule to 3h and rotated; this instance's
  // snapshot still describes the world before that.
  const snapshot = { id: ID, intervalHours: 24, lastTheme: "White", lastRotated: 100 }
  const live = { id: ID, intervalHours: 3, lastTheme: "Nord", lastRotated: 900 }
  const entry = Merge.mergeEntry(ID, snapshot, live, { paused: true })
  assert.deepEqual(entry, { id: ID, intervalHours: 3, lastTheme: "Nord", lastRotated: 900, paused: true })
})

test("mergeEntry carries over a key only the snapshot knows about", () => {
  // The window between another instance's write and this instance's file
  // watcher seeing it: whatever the live entry hasn't caught up on yet must
  // survive the write instead of being dropped from the file.
  const snapshot = { id: ID, mode: "interval", followSun: true }
  const live = { id: ID, mode: "interval" }
  assert.equal(Merge.mergeEntry(ID, snapshot, live, { paused: true }).followSun, true)
})

test("mergeEntry carries over a key only the live entry knows about", () => {
  const snapshot = { id: ID, mode: "interval" }
  const live = { id: ID, mode: "interval", includedThemes: ["Nord"] }
  assert.deepEqual(Merge.mergeEntry(ID, snapshot, live, {}).includedThemes, ["Nord"])
})

test("mergeEntry never loses a key, whichever side holds it", () => {
  // The property stated in prose above, checked over every split of a full
  // entry between the two bases.
  const full = {
    mode: "interval", intervalHours: 6, lastRotated: 42, lastTheme: "Nord",
    followSun: true, paused: false, lastPeriod: "day", includedThemes: ["Nord", "Gruvbox"]
  }
  const keys = Object.keys(full)
  for (let mask = 0; mask < (1 << keys.length); mask++) {
    const snapshot = { id: ID }
    const live = { id: ID }
    keys.forEach((key, i) => {
      if (mask & (1 << i)) live[key] = full[key]
      else snapshot[key] = full[key]
    })
    const entry = Merge.mergeEntry(ID, snapshot, live, { lastRotated: 99 })
    for (const key of keys)
      assert.deepEqual(entry[key], key === "lastRotated" ? 99 : full[key],
        "lost " + key + " at split " + mask)
  }
})

test("mergeEntry tolerates missing bases", () => {
  assert.deepEqual(Merge.mergeEntry(ID, null, null, null), { id: ID })
  assert.deepEqual(Merge.mergeEntry(ID, undefined, undefined, { paused: true }), { id: ID, paused: true })
})

test("settingValue prefers the live entry and falls back per key", () => {
  const live = { mode: "interval" }
  const snapshot = { mode: "off", intervalHours: 12 }
  assert.equal(Merge.settingValue(live, snapshot, "mode", "off"), "interval")
  assert.equal(Merge.settingValue(live, snapshot, "intervalHours", 6), 12)
  assert.equal(Merge.settingValue(live, snapshot, "missing", "fallback"), "fallback")
  assert.equal(Merge.settingValue(null, null, "mode", "off"), "off")
})

test("settingValue treats false and 0 as values, not misses", () => {
  // `paused: false` reading through to a stale `paused: true` snapshot would
  // silently un-pause the widget.
  assert.equal(Merge.settingValue({ paused: false }, { paused: true }, "paused", true), false)
  assert.equal(Merge.settingValue({ lastRotated: 0 }, { lastRotated: 5 }, "lastRotated", 1), 0)
  // null and undefined are misses, so a key the live entry hasn't got yet
  // still resolves from the snapshot.
  assert.equal(Merge.settingValue({ paused: null }, { paused: true }, "paused", false), true)
})

test("mergeOverrides keeps the latest value of each queued key", () => {
  assert.deepEqual(
    Merge.mergeOverrides({ paused: true, lastRotated: 1 }, { paused: false }),
    { paused: false, lastRotated: 1 })
  assert.deepEqual(Merge.mergeOverrides(null, { paused: true }), { paused: true })
  assert.deepEqual(Merge.mergeOverrides({ paused: true }, null), { paused: true })
})
