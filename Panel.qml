import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon + popup for randomizing/auto-rotating the Omarchy theme.
//
// Three things this offers, all from the one popup:
//   - "Random Theme Now": one-shot manual rotation.
//   - Auto-rotate mode: Off / every 1-12h / Daily, picked via a ButtonGroup.
//   - The background check that actually does the auto-rotating: a Timer
//     that polls every minute (cheap, wall-clock based via Date.now() so it
//     self-corrects across suspend/resume) and fires when the configured
//     interval has elapsed since the last rotation.
//
// State (mode, intervalHours, lastRotated, lastTheme) lives in this widget's
// shell.json entry, following the same settings + updateEntryInline pattern
// as the built-in clock/power widgets, so it survives shell restarts.
Panel {
  id: root
  moduleName: "tim.theme-rotate"
  ipcTarget: "tim.theme-rotate"
  manageIpc: false

  readonly property string mode: setting("mode", "off")
  readonly property int intervalHours: parseInt(setting("intervalHours", 6), 10) || 6
  readonly property real lastRotated: Number(setting("lastRotated", 0)) || 0
  readonly property string lastTheme: setting("lastTheme", "")
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

  function rotateNow() {
    if (root.busy || rotateProc.running) return
    root.busy = true
    rotateProc.running = true
  }

  function checkDue() {
    if (root.mode !== "interval") return
    if (root.busy || rotateProc.running) return
    var dueAt = root.lastRotated + root.intervalHours * 3600000
    if (Date.now() >= dueAt) root.rotateNow()
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

  function open() { root.controller.show(); root.refreshCurrent() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  Component.onCompleted: root.refreshCurrent()
  onOpenedChanged: if (opened) root.refreshCurrent()

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: currentProc
    command: ["omarchy", "theme", "current"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.currentTheme = String(text || "").trim() }
  }

  Process {
    id: rotateProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/tim.theme-rotate/bin/rotate-random.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        if (name !== "") {
          root.currentTheme = name
          root.persist({ lastRotated: Date.now(), lastTheme: name })
        }
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
    onTriggered: root._tick++
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

        Button {
          width: parent.width
          text: root.busy ? "Rotating…" : "🎲  Random Theme Now"
          bordered: true
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          fontSize: Style.font.body
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          iconSpinning: root.busy
          onClicked: root.rotateNow()
        }
      }
    }
  }
}
