import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon + popup for randomizing/auto-rotating the Omarchy theme.
//
// Four things this offers, all from the one popup:
//   - "Random Theme Now": one-shot manual rotation.
//   - Auto-rotate mode: Off / every 1-12h / Daily, picked via a ButtonGroup.
//   - Follow the sun: restrict the pool to light themes after sunrise and
//     dark themes after sunset (and swap as soon as the period changes).
//   - The background check that actually does the auto-rotating: a Timer
//     that polls every minute (cheap, wall-clock based via Date.now() so it
//     self-corrects across suspend/resume) and fires when the configured
//     interval has elapsed since the last rotation.
//
// State (mode, intervalHours, lastRotated, lastTheme, followSun) lives in
// this widget's shell.json entry, following the same settings +
// updateEntryInline pattern as the built-in clock/power widgets, so it
// survives shell restarts.
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
  readonly property string lastPeriod: setting("lastPeriod", "")
  readonly property string modeValue: mode === "interval" ? String(intervalHours) : "off"

  readonly property var rotateOptions: [
    { value: "off", label: "Off" },
    { value: "1", label: "1h" },
    { value: "3", label: "3h" },
    { value: "6", label: "6h" },
    { value: "12", label: "12h" },
    { value: "24", label: "Daily" }
  ]

  property string currentTheme: ""
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
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var k in overrides) entry[k] = overrides[k]
    root.settings = entry
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

  function pluginBin(name) {
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/tim.theme-rotate/bin/" + name
  }

  function rotateCommand(ifNeeded) {
    var cmd = [root.pluginBin("rotate-random.sh")]
    if (root.followSun) cmd.push("--follow-sun")
    if (ifNeeded) cmd.push("--if-needed")
    return cmd
  }

  function rotateNow(ifNeeded) {
    if (root.busy || rotateProc.running) return
    root.rotateIfNeeded = !!ifNeeded
    if (!ifNeeded) root.busy = true
    rotateProc.command = root.rotateCommand(!!ifNeeded)
    rotateProc.running = true
  }

  function setFollowSun(on) {
    var entry = { followSun: !!on }
    if (!on) entry.lastPeriod = ""
    root.persist(entry)
    if (on) {
      root.refreshSun()
      root.rotateNow(true)
    }
  }

  function checkDue() {
    if (root.busy || rotateProc.running) return
    var intervalDue = false
    if (root.mode === "interval") {
      var dueAt = root.lastRotated + root.intervalHours * 3600000
      intervalDue = Date.now() >= dueAt
    }
    if (intervalDue) {
      root.rotateNow(false)
      return
    }
    // Catch sunrise/sunset (and resume-from-sleep) without waiting for
    // the next scheduled interval: switch pools as soon as the period
    // no longer matches the last applied one.
    if (root.followSun) root.rotateNow(true)
  }

  function nextDueText() {
    root._tick // create a binding dependency so this re-evaluates on tick
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

  function open() { root.controller.show(); root.refreshCurrent(); root.refreshSun() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  Component.onCompleted: { root.refreshCurrent(); root.refreshSun() }
  onOpenedChanged: if (opened) { root.refreshCurrent(); root.refreshSun() }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: currentProc
    command: ["omarchy", "theme", "current"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.currentTheme = String(text || "").trim() }
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
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🔀"
    slotSize: Style.bar.iconSlot
    tooltipText: "Theme Rotate"
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
          visible: root.mode === "interval"
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
          onClicked: root.rotateNow(false)
        }
      }
    }
  }
}
