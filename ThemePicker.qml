import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Fullscreen overlay for choosing which installed themes take part in the
// rotation. Every theme is a wallpaper tile; clicking one adds or removes it.
//
// Selection model, and why it is "empty means all": the widget persists an
// explicit list of theme names, but an empty list is treated as "every
// installed theme". That keeps a freshly-installed theme in the rotation for
// users who never touched this screen, and it is why `emitChange` normalizes
// a fully-checked grid back to an empty list instead of writing all 31 names
// — otherwise turning everything on would silently freeze the rotation set at
// whatever was installed the day the user opened this.
//
// At least one theme must stay checked. A pool of zero would leave the
// rotator with nothing to pick, so the last tile refuses to turn off and
// says why rather than quietly falling back to something else.
PanelWindow {
  id: root

  property Item anchorItem: null
  property bool open: false
  // [{ name, slug, mode, image, color }], from bin/list-themes.sh.
  property var themes: []
  // Persisted selection. Empty array === every theme.
  property var selected: []
  property string currentTheme: ""
  property bool loading: false
  property string fontFamily: Style.font.family

  signal selectionEdited(var names)
  signal closeRequested()
  signal refreshRequested()

  // name -> bool, the live state of the grid while the overlay is open.
  property var picked: ({})
  property string notice: ""

  readonly property color foreground: Color.menu.text
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property int cardMinWidth: Style.space(196)
  readonly property int cardGap: Style.space(10)

  function arrayFrom(v) {
    if (!v || typeof v.length !== "number" || typeof v === "string") return []
    var out = []
    for (var i = 0; i < v.length; i++) out.push(v[i])
    return out
  }

  function syncPicked() {
    var chosen = arrayFrom(root.selected)
    var all = chosen.length === 0
    var map = ({})
    var list = arrayFrom(root.themes)
    for (var i = 0; i < list.length; i++) {
      var name = String(list[i].name)
      map[name] = all || chosen.indexOf(name) !== -1
    }
    root.picked = map
  }

  function isPicked(name) {
    return !!root.picked[String(name)]
  }

  function pickedCount() {
    var list = arrayFrom(root.themes)
    var n = 0
    for (var i = 0; i < list.length; i++) if (isPicked(list[i].name)) n++
    return n
  }

  function emitChange() {
    var list = arrayFrom(root.themes)
    // Only a visible, loaded picker may write the selection. A closed or
    // still-loading instance — including one left over from a plugin
    // hot-reload — would otherwise be able to persist a pool built from a
    // partial theme list.
    if (!root.open || list.length === 0) return
    var names = []
    for (var i = 0; i < list.length; i++) if (isPicked(list[i].name)) names.push(String(list[i].name))
    // All of them selected is stored as "no restriction" so themes installed
    // later join the rotation instead of being silently left out.
    root.selectionEdited(names.length === list.length ? [] : names)
  }

  function toggle(name) {
    var key = String(name)
    if (isPicked(key) && pickedCount() <= 1) {
      root.notice = "At least one theme has to stay in the rotation."
      noticeTimer.restart()
      return
    }
    var map = ({})
    for (var k in root.picked) map[k] = root.picked[k]
    map[key] = !map[key]
    root.picked = map
    root.notice = ""
    emitChange()
  }

  function selectAll() {
    var list = arrayFrom(root.themes)
    var map = ({})
    for (var i = 0; i < list.length; i++) map[String(list[i].name)] = true
    root.picked = map
    root.notice = ""
    emitChange()
  }

  // Everything that matches light or dark, so "only dark themes at any hour"
  // is one click instead of twenty-odd.
  function selectMode(mode) {
    var list = arrayFrom(root.themes)
    var map = ({})
    var n = 0
    for (var i = 0; i < list.length; i++) {
      var on = String(list[i].mode) === mode
      map[String(list[i].name)] = on
      if (on) n++
    }
    if (n === 0) {
      root.notice = "No " + mode + " themes are installed."
      noticeTimer.restart()
      return
    }
    root.picked = map
    root.notice = ""
    emitChange()
  }

  // Percent-encode each path segment: theme directories in ~/.config can
  // contain spaces, which a bare file:// string would not survive.
  function fileUrl(path) {
    var p = String(path || "")
    if (p === "") return ""
    return "file://" + p.split("/").map(encodeURIComponent).join("/")
  }

  function summaryText() {
    var total = arrayFrom(root.themes).length
    if (total === 0) return root.loading ? "Loading themes…" : "No themes found"
    var n = pickedCount()
    return n >= total ? ("All " + total + " themes in rotation")
                      : (n + " of " + total + " themes in rotation")
  }

  onThemesChanged: syncPicked()
  onSelectedChanged: syncPicked()
  onOpenChanged: {
    if (open) {
      root.notice = ""
      syncPicked()
      root.refreshRequested()
      Qt.callLater(function() {
        if (root.open) grid.forceActiveFocus()
      })
    }
  }

  Timer {
    id: noticeTimer
    interval: 2600
    onTriggered: root.notice = ""
  }

  screen: anchorItem && anchorItem.QsWindow.window ? anchorItem.QsWindow.window.screen : null
  visible: open
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "tim-theme-rotate-picker"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  anchors { top: true; bottom: true; left: true; right: true }

  // Near-opaque wash in the menu background color rather than the themed
  // scrim: the tiles below are full-bleed wallpapers, and a half-transparent
  // scrim over the live desktop left the captions hard to read.
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.menu.background, 0.95)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  Item {
    id: frame
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(64), Style.space(1180))
    height: parent.height - Style.space(80)

    // The card sits on the scrim; clicks inside it must not reach the
    // dismissal MouseArea behind.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Column {
      anchors.fill: parent
      spacing: Style.space(12)

      Item {
        id: headerRow
        width: parent.width
        height: Math.max(header.implicitHeight, actions.implicitHeight)

        Column {
          id: header
          anchors.left: parent.left
          anchors.right: actions.left
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.labelGap

          Text {
            text: "Themes in rotation"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.notice !== "" ? root.notice : root.summaryText()
            color: root.notice !== "" ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          id: actions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.md

          Button {
            text: "All"
            tooltipText: "Put every installed theme back in the rotation"
            bordered: true
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.selectAll()
          }

          Button {
            text: "Dark only"
            bordered: true
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.selectMode("dark")
          }

          Button {
            text: "Light only"
            bordered: true
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.selectMode("light")
          }

          Button {
            text: "Done"
            bordered: true
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.closeRequested()
          }
        }
      }

      GridView {
        id: grid
        width: parent.width
        height: parent.height - headerRow.height - footer.implicitHeight - Style.space(12) * 2
        clip: true
        focus: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.themes
        currentIndex: 0
        cacheBuffer: Style.space(600)

        readonly property int columns: Math.max(1, Math.floor(width / (root.cardMinWidth + root.cardGap)))
        cellWidth: Math.floor(width / columns)
        // 16:10 wallpaper plus a caption strip.
        cellHeight: Math.round((cellWidth - root.cardGap) * 0.625) + Style.space(30) + root.cardGap

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.closeRequested(); event.accepted = true
          } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var item = root.arrayFrom(root.themes)[grid.currentIndex]
            if (item) root.toggle(item.name)
            event.accepted = true
          } else if (event.text === "h") {
            grid.moveCurrentIndexLeft(); event.accepted = true
          } else if (event.text === "l") {
            grid.moveCurrentIndexRight(); event.accepted = true
          } else if (event.text === "j") {
            grid.moveCurrentIndexDown(); event.accepted = true
          } else if (event.text === "k") {
            grid.moveCurrentIndexUp(); event.accepted = true
          } else if (event.text === "a") {
            root.selectAll(); event.accepted = true
          }
        }

        delegate: Item {
          id: cell
          required property var modelData
          required property int index

          readonly property bool chosen: root.isPicked(modelData.name)
          readonly property bool isCurrent: String(modelData.name) === root.currentTheme
          readonly property bool hot: hover.containsMouse || grid.currentIndex === index

          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            id: card
            anchors.fill: parent
            anchors.rightMargin: root.cardGap
            anchors.bottomMargin: root.cardGap
            radius: Style.cornerRadius
            color: Color.menu.background
            border.width: cell.chosen ? Math.max(2, Style.space(2)) : 1
            border.color: cell.chosen
              ? (cell.hot ? Color.accent : Util.alpha(Color.accent, 0.8))
              : (cell.hot ? Util.alpha(root.foreground, 0.55) : Util.alpha(root.foreground, 0.18))

            Item {
              id: shot
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: card.border.width
              height: card.height - caption.height - card.border.width * 2
              clip: true
              opacity: cell.chosen ? 1.0 : 0.28

              Behavior on opacity { NumberAnimation { duration: 120 } }

              // Themes without any wallpaper still get a tile: their own
              // background color, so the grid never shows an empty hole.
              Rectangle {
                anchors.fill: parent
                color: String(cell.modelData.color || "") !== "" ? cell.modelData.color : Color.menu.background
              }

              Image {
                anchors.fill: parent
                source: root.fileUrl(cell.modelData.image)
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: Math.round(grid.cellWidth * 1.4)
              }
            }

            // Selected badge.
            Rectangle {
              anchors.right: shot.right
              anchors.top: shot.top
              anchors.margins: Style.space(6)
              width: Style.space(20)
              height: width
              radius: width / 2
              visible: cell.chosen
              color: Color.accent

              Text {
                anchors.centerIn: parent
                text: "✓"
                color: Color.menu.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            Rectangle {
              anchors.left: shot.left
              anchors.top: shot.top
              anchors.margins: Style.space(6)
              visible: cell.isCurrent
              radius: Style.cornerRadius
              color: Util.alpha(Color.menu.background, 0.8)
              width: currentLabel.implicitWidth + Style.space(10)
              height: currentLabel.implicitHeight + Style.space(4)

              Text {
                id: currentLabel
                anchors.centerIn: parent
                text: "current"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              id: caption
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: card.border.width
              height: Style.space(28)

              Text {
                anchors.left: parent.left
                anchors.right: modeGlyph.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(6)
                text: cell.modelData.name
                elide: Text.ElideRight
                color: cell.chosen ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: cell.chosen
              }

              Text {
                id: modeGlyph
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(8)
                text: String(cell.modelData.mode) === "light" ? "☀" : "☾"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          MouseArea {
            id: hover
            anchors.fill: card
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              grid.currentIndex = cell.index
              root.toggle(cell.modelData.name)
            }
          }
        }
      }

      Text {
        id: footer
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Click a wallpaper to include or exclude it · Space toggles · Esc closes"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
