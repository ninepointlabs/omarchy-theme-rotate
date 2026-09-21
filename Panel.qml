import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SettingsMerge.js" as SettingsMerge

// Bar icon + popup for randomizing/auto-rotating the Omarchy theme.
//
// What this offers, all from the one popup:
//   - "Random Theme Now": one-shot manual rotation.
//   - Auto-rotate mode: Off / every 1-12h / Daily, picked via a ButtonGroup.
//   - Pause: freeze on the current theme without losing the schedule you
//     set, and without the day/night swap yanking it away either.
//   - Follow the sun: restrict the pool to light themes after sunrise and
//     dark themes after sunset (and swap as soon as the period changes).
//   - Choose themes: a fullscreen wallpaper grid (ThemePicker.qml) for
//     picking which installed themes are eligible at all.
//   - The background check that actually does the auto-rotating: a Timer
//     that polls every minute (cheap, wall-clock based via Date.now() so it
//     self-corrects across suspend/resume) and fires when the configured
//     interval has elapsed since the last rotation.
//
// State (mode, intervalHours, lastRotated, lastTheme, followSun, paused,
// includedThemes) lives in this widget's shell.json entry, written through
// updateEntryInline like the built-in clock/power widgets, so it survives
// shell restarts. Reads and writes go through the live file rather than the
// injected snapshot — see "authoritative settings" below for why.
Panel {
  id: root
  moduleName: "tim.theme-rotate"
  ipcTarget: "tim.theme-rotate"
  manageIpc: false

  readonly property string mode: setting("mode", "off")
  readonly property int intervalHours: parseInt(setting("intervalHours", 6), 10) || 6
  readonly property real lastRotated: Number(setting("lastRotated", 0)) || 0
  readonly property string lastTheme: setting("lastTheme", "")
  readonly property bool followSun: !!setting("followSun", false)
  readonly property bool paused: !!setting("paused", false)
  // Theme names eligible for rotation. Empty === every installed theme, so
  // a theme installed later joins in without the user revisiting the picker.
  readonly property var includedThemes: root.namesFrom(setting("includedThemes", []))
  readonly property string lastPeriod: setting("lastPeriod", "")
  readonly property string modeValue: mode === "interval" ? String(intervalHours) : "off"

  // ------------------------------------------------- authoritative settings
  //
  // The shell injects a `settings` snapshot into each widget instance. There
  // is one instance per monitor, and a plugin hot-reload leaves the previous
  // instances running with the snapshot they were built with — they keep
  // their timers and their IPC handler. Merging a write onto that snapshot
  // silently drops whatever another instance persisted in the meantime; a
  // `paused: false` written by one instance disappeared exactly this way when
  // another instance saved a theme selection a minute later.
  //
  // So shell.json itself is the source of truth here: every read prefers the
  // live entry, and every write merges onto the live entry instead of the
  // snapshot. The shell writes that file atomically, so a watcher only ever
  // sees whole documents, and it updates `shellConfig` in-process before the
  // write, so nothing downstream depends on our read latency.
  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  property var liveEntry: null
  property bool configLoaded: false
  property var pendingOverrides: null

  function entryFromConfig(text) {
    return SettingsMerge.entryFromConfig(text, root.moduleName)
  }

  function applyLiveConfig(text) {
    var entry = root.entryFromConfig(text)
    if (entry) root.liveEntry = entry
    root.configLoaded = true
    if (!root.pendingOverrides) return
    var queued = root.pendingOverrides
    root.pendingOverrides = null
    root.persist(queued)
  }

  // Overrides Panel.setting() so every binding below reads the live entry and
  // re-evaluates when it changes, falling back to the injected snapshot for
  // keys the live entry doesn't carry (and entirely, until the first read
  // lands or if shell.json can't be read at all).
  function setting(name, fallback) {
    return SettingsMerge.settingValue(root.liveEntry, root.settings, name, fallback)
  }

  readonly property var rotateOptions: [
    { value: "off", label: "Off" },
    { value: "1", label: "1h" },
    { value: "3", label: "3h" },
    { value: "6", label: "6h" },
    { value: "12", label: "12h" },
    { value: "24", label: "Daily" }
  ]

  property string currentTheme: ""
  // [{ name, slug, mode, image, color }] from bin/list-themes.sh, used by
  // the picker overlay and the "n of m themes" summary.
  property var themes: []
  property bool themesLoading: false
  property bool busy: false
  property bool rotateIfNeeded: false
  property string sunPeriod: ""
  property string sunSunrise: ""
  property string sunSunset: ""
  property string sunSource: ""

  // Bumped by a ticker Timer while the panel is open, purely so the
  // "next rotation in" text is referenced here and recomputes on a cadence
  // instead of freezing at the value from when the popup opened.
  property int _tick: 0

  function persist(overrides) {
    // Before the first read of shell.json, hold the write rather than guess a
    // base: an empty or stale one would erase keys this instance has never
    // seen. Queued overrides merge, so only the latest value of each survives.
    if (!root.configLoaded) {
      root.pendingOverrides = SettingsMerge.mergeOverrides(root.pendingOverrides, overrides)
      return
    }
    var entry = SettingsMerge.mergeEntry(root.moduleName, root.settings, root.liveEntry, overrides)
    root.settings = entry
    // Adopt our own write immediately. The watcher confirms it a moment later;
    // until then this instance must not merge onto a base that predates it.
    root.liveEntry = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setMode(v) {
    if (v === "off") root.persist({ mode: "off" })
    // Reset the clock on every mode/interval change so flipping it on
    // doesn't immediately fire a rotation — the user gets a full interval
    // from the moment they chose it.
    else root.persist({ mode: "interval", intervalHours: parseInt(v, 10) || 6, lastRotated: Date.now() })
  }

  function refreshCurrent() {
    if (!currentProc.running) currentProc.running = true
  }

  // settings values arrive as JSValue lists that can fail Array.isArray;
  // normalize anything array-like into a plain array of non-empty strings.
  function namesFrom(v) {
    var out = []
    if (!v || typeof v.length !== "number" || typeof v === "string") return out
    for (var i = 0; i < v.length; i++) {
      var s = String(v[i])
      if (s !== "") out.push(s)
    }
    return out
  }

  function refreshThemes() {
    if (listProc.running) return
    root.themesLoading = true
    listProc.running = true
  }

  function parseThemes(text) {
    var out = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length < 3 || parts[0] === "") continue
      out.push({
        name: parts[0],
        slug: parts[1],
        mode: parts[2],
        image: parts.length > 3 ? parts[3] : "",
        color: parts.length > 4 ? parts[4] : ""
      })
    }
    return out
  }

  // How many of the persisted names are actually installed. Names left over
  // from a since-removed theme shouldn't inflate the count in the popup.
  function includedInstalledCount() {
    var n = 0
    for (var i = 0; i < root.themes.length; i++)
      if (root.includedThemes.indexOf(String(root.themes[i].name)) !== -1) n++
    return n
  }

  function poolText() {
    if (root.themes.length === 0) return root.themesLoading ? "Loading installed themes…" : ""
    var n = root.includedInstalledCount()
    if (root.includedThemes.length === 0 || n === 0 || n >= root.themes.length)
      return "All " + root.themes.length + " installed themes"
    return n + " of " + root.themes.length + " themes selected"
  }

  function pluginBin(name) {
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/tim.theme-rotate/bin/" + name
  }

  function rotateCommand(ifNeeded, debounce) {
    var cmd = [root.pluginBin("rotate-random.sh")]
    if (root.followSun) cmd.push("--follow-sun")
    if (ifNeeded) cmd.push("--if-needed")
    if (debounce) {
      cmd.push("--debounce-ms")
      cmd.push(String(root.autoDebounceMs))
    }
    for (var i = 0; i < root.includedThemes.length; i++) {
      cmd.push("--only")
      cmd.push(root.includedThemes[i])
    }
    return cmd
  }

  // Every instance of this widget — one per monitor, plus any left behind by
  // a plugin hot-reload — runs its own due check. Live settings keep them
  // from disagreeing about when the last rotation was, but two instances can
  // still reach the same deadline in the same instant, before either has
  // written anything. An automatic rotation therefore asks the script to
  // debounce: the first run applies a theme and records when, and any run
  // that starts inside the window keeps the theme instead of shuffling a
  // second time. Manual rotations never debounce — pressing the button twice
  // is a deliberate second shuffle.
  readonly property int autoDebounceMs: 15000

  function rotateNow(ifNeeded, debounce) {
    if (root.busy || rotateProc.running) return
    root.rotateIfNeeded = !!ifNeeded
    if (!ifNeeded) root.busy = true
    rotateProc.command = root.rotateCommand(!!ifNeeded, !!debounce)
    rotateProc.running = true
  }

  function setFollowSun(on) {
    var entry = { followSun: !!on }
    if (!on) entry.lastPeriod = ""
    root.persist(entry)
    // Paused means paused: turning day/night on while frozen arms the
    // feature without moving off the theme the user parked on.
    if (on && !root.paused) {
      root.refreshSun()
      root.rotateNow(true, true)
    }
  }

  // Pausing stops the clock entirely — no interval rotation and no day/night
  // swap — while leaving mode, interval, and follow-sun exactly as they were
  // so resuming puts the user back where they left off.
  function setPaused(on) {
    if (on) {
      root.persist({ paused: true })
      return
    }
    // Resuming starts a fresh interval instead of firing immediately for
    // time that elapsed while paused, then catches up on the sun if needed.
    root.persist({ paused: false, lastRotated: Date.now() })
    if (root.followSun) {
      root.refreshSun()
      root.rotateNow(true, true)
    }
  }

  function setThemePool(names) {
    root.persist({ includedThemes: root.namesFrom(names) })
  }

  function checkDue() {
    if (root.paused) return
    if (root.busy || rotateProc.running) return
    var intervalDue = false
    if (root.mode === "interval") {
      var dueAt = root.lastRotated + root.intervalHours * 3600000
      intervalDue = Date.now() >= dueAt
    }
    if (intervalDue) {
      root.rotateNow(false, true)
      return
    }
    // Catch sunrise/sunset (and resume-from-sleep) without waiting for
    // the next scheduled interval: switch pools as soon as the period
    // no longer matches the last applied one.
    if (root.followSun) root.rotateNow(true, true)
  }

  function nextDueText() {
    root._tick // create a binding dependency so this re-evaluates on tick
    if (root.paused) return "Paused" + (root.currentTheme ? " on " + root.currentTheme : "")
    if (root.mode !== "interval") return ""
    if (root.lastRotated <= 0) return "Rotates within " + root.intervalHours + "h"
    var remainingMs = (root.lastRotated + root.intervalHours * 3600000) - Date.now()
    if (remainingMs <= 0) return "Rotating soon…"
    var totalMin = Math.round(remainingMs / 60000)
    var h = Math.floor(totalMin / 60)
    var m = totalMin % 60
    return h > 0 ? ("Next rotation in " + h + "h " + m + "m") : ("Next rotation in " + m + "m")
  }

  function refreshSun() {
    if (!sunProc.running) sunProc.running = true
  }

  function sunStatusText() {
    if (!root.followSun) return ""
    if (root.paused) return "Paused — day and night won't switch the theme"
    if (root.sunPeriod === "") return "Looking up sunrise and sunset…"
    var when = root.sunPeriod === "day" ? "Daytime · light themes" : "Night · dark themes"
    var times = []
    if (root.sunSunrise !== "") times.push("sunrise " + root.sunSunrise)
    if (root.sunSunset !== "") times.push("sunset " + root.sunSunset)
    return times.length ? (when + " · " + times.join(" · ")) : when
  }

  function randomButtonText() {
    if (root.busy) return "Rotating…"
    if (!root.followSun) return "🎲  Random Theme Now"
    if (root.sunPeriod === "day") return "🎲  Random Day Theme"
    if (root.sunPeriod === "night") return "🎲  Random Night Theme"
    return "🎲  Random Theme Now"
  }

  function open() { root.controller.show(); root.refreshCurrent(); root.refreshSun(); root.refreshThemes() }

  function openPicker() {
    // One layer-shell surface with keyboard focus at a time: the popup gets
    // out of the way before the fullscreen grid takes over.
    root.close()
    root.refreshCurrent()
    picker.open = true
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  Component.onCompleted: { root.refreshCurrent(); root.refreshSun() }
  onOpenedChanged: if (opened) { root.refreshCurrent(); root.refreshSun(); root.refreshThemes() }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Same pattern the shell itself uses for this file: watch, reload on
  // change, parse on load. printErrors stays off because a missing
  // shell.json is a normal first-run state, not something to log about.
  FileView {
    id: configFile
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyLiveConfig(text())
    // Unreadable config: fall back to the injected snapshot rather than
    // holding every write forever.
    onLoadFailed: function(error) { root.applyLiveConfig("") }
    onFileChanged: reload()
  }

  Process {
    id: currentProc
    command: ["omarchy", "theme", "current"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.currentTheme = String(text || "").trim() }
  }

  Process {
    id: listProc
    command: [root.pluginBin("list-themes.sh")]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.themes = root.parseThemes(text) }
    onExited: root.themesLoading = false
  }

  Process {
    id: sunProc
    command: [root.pluginBin("sun-status.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim().split("\n").pop() || ""
        var parts = line.split("\t")
        if (parts.length >= 1 && parts[0] !== "") root.sunPeriod = parts[0]
        if (parts.length >= 2) root.sunSunrise = parts[1]
        if (parts.length >= 3) root.sunSunset = parts[2]
        if (parts.length >= 4) root.sunSource = parts[3]
      }
    }
  }

  Process {
    id: rotateProc
    command: [root.pluginBin("rotate-random.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim().split("\n").pop() || ""
        var parts = line.split("\t")
        var action = parts.length > 1 ? parts[0] : "set"
        var name = parts.length > 1 ? parts[1] : parts[0]
        name = String(name || "").trim()
        if (name === "") return
        root.currentTheme = name
        var entry = { lastTheme: name }
        if (root.followSun && root.sunPeriod !== "") entry.lastPeriod = root.sunPeriod
        if (action !== "keep") entry.lastRotated = Date.now()
        else if (!root.rotateIfNeeded) entry.lastRotated = Date.now()
        root.persist(entry)
      }
    }
    onExited: root.busy = false
  }

  // Wall-clock poll: cheap, and Date.now()-based so a laptop sleeping
  // through part of the interval still catches up correctly on resume
  // instead of losing that time the way a plain interval Timer would.
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkDue()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: {
      root._tick++
      if (root.followSun) root.refreshSun()
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Jump straight to the wallpaper grid, e.g. from a Hyprland bind.
    function themes(): void { root.openPicker() }
    function pause(): void { root.setPaused(true) }
    function resume(): void { root.setPaused(false) }
    function togglePause(): void { root.setPaused(!root.paused) }
    function random(): void { root.rotateNow(false, false) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.paused ? "⏸" : "🔀"
    slotSize: Style.bar.iconSlot
    tooltipText: root.paused ? "Theme Rotate — paused" : "Theme Rotate"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Text {
          text: "Theme Rotation"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          text: "Current: " + (root.currentTheme || "—")
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Button {
          width: parent.width
          text: root.paused ? "▶  Resume rotation" : "⏸  Pause rotation"
          tooltipText: root.paused
            ? "Start rotating again from a fresh interval"
            : "Stay on the current theme until you resume"
          bordered: true
          selected: root.paused
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.body
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.setPaused(!root.paused)
        }

        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: "AUTO-ROTATE"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        ButtonGroup {
          width: parent.width
          options: root.rotateOptions
          value: root.modeValue
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.bodySmall
          onChanged: function(v) { root.setMode(v) }
        }

        Text {
          visible: root.paused || root.mode === "interval"
          text: root.nextDueText()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: "DAY / NIGHT"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Toggle {
          width: parent.width
          label: "Follow the sun"
          description: "Random light theme after sunrise, random dark theme after sunset."
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          checked: root.followSun
          onClicked: root.setFollowSun(!root.followSun)
        }

        Text {
          visible: root.followSun
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.sunStatusText()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: "THEMES"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Button {
          width: parent.width
          text: "🖼  Choose themes…"
          tooltipText: "Pick which installed themes the rotation is allowed to use"
          bordered: true
          leftAlign: true
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.body
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.openPicker()
        }

        Text {
          visible: text !== ""
          width: parent.width
          elide: Text.ElideRight
          text: root.poolText()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.bar.foreground }

        Button {
          width: parent.width
          text: root.randomButtonText()
          bordered: true
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.body
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          iconSpinning: root.busy
          onClicked: root.rotateNow(false, false)
        }
      }
    }
  }

  ThemePicker {
    id: picker
    anchorItem: button
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    themes: root.themes
    selected: root.includedThemes
    currentTheme: root.currentTheme
    loading: root.themesLoading
    onSelectionEdited: function(names) { root.setThemePool(names) }
    onRefreshRequested: root.refreshThemes()
    onCloseRequested: picker.open = false
  }
}
