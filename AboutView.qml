import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "About.js" as About

// The popup's About page: who made Theme Rotate, its version and license,
// where to get help, and what it does with your data. Panel.qml swaps it in
// for the main controls (info button, `i`, or the `about` IPC call).
Column {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string version: ""
  property string licenseText: ""
  property var versions: ({ quickshell: "", qt: "", omarchy: "" })
  property bool showLicense: false
  property string notice: ""

  signal backRequested()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string details: About.details(root.version, root.versions,
    Quickshell.env("XDG_CURRENT_DESKTOP") || "")
  readonly property real labelWidth: Style.space(72)

  function copy(text, what) {
    Quickshell.clipboardText = text
    root.notice = what + " copied"
    noticeTimer.restart()
  }

  spacing: Style.space(12)
  onVisibleChanged: if (!visible) { root.showLicense = false; root.notice = "" }

  Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }

  Item {
    width: parent.width
    height: backButton.implicitHeight

    Button {
      id: backButton
      iconText: "󰁍"
      text: "Back"
      tooltipText: "Back to Theme Rotation (Esc)"
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.backRequested()
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(14)

    Text {
      id: appIcon
      text: "󰒝"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.display * 1.5
      anchors.verticalCenter: parent.verticalCenter
    }

    Column {
      width: parent.width - appIcon.width - parent.spacing
      spacing: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        text: About.NAME
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: About.TAGLINE
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        objectName: "aboutVersion"
        text: "Version " + (root.version || "unknown")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  PanelSeparator { foreground: root.foreground }

  Grid {
    width: parent.width
    columns: 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(8)
    verticalItemAlignment: Grid.AlignVCenter

    Text { width: root.labelWidth; text: "Made by"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Text { text: About.ORGANIZATION; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }

    Text { width: root.labelWidth; text: "Created"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Text { text: About.CREATED; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }

    Text { width: root.labelWidth; text: "License"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Row {
      spacing: Style.space(6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: About.licenseSummary(root.licenseText) || "MIT License"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        objectName: "aboutLicense"
        text: root.showLicense ? "Hide" : "Read it"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: root.showLicense = !root.showLicense
      }
    }

    Text { width: root.labelWidth; text: "Support"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
    Row {
      spacing: Style.space(6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: About.SUPPORT_EMAIL
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        text: "Email"
        tooltipText: "Opens your mail app with the version details filled in"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: Qt.openUrlExternally(About.mailto(root.version, root.details))
      }
      Button {
        text: "Copy"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: root.copy(About.SUPPORT_EMAIL, "Address")
      }
    }
  }

  Text {
    width: parent.width
    text: "PRIVACY"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
  Text {
    objectName: "aboutPrivacy"
    width: parent.width
    wrapMode: Text.WordWrap
    text: About.PRIVACY
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Built with " + About.builtWith(root.versions)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    width: parent.width
    height: Style.space(150)
    visible: root.showLicense
    color: "transparent"
    radius: Style.cornerRadius
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

    Flickable {
      id: licenseView
      anchors.fill: parent
      anchors.margins: Style.space(8)
      clip: true
      contentHeight: licenseBody.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Text {
        id: licenseBody
        objectName: "aboutLicenseText"
        width: licenseView.width
        wrapMode: Text.WordWrap
        text: About.licenseBody(root.licenseText) || "LICENSE could not be read from the plugin folder."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(8)
    layoutDirection: Qt.RightToLeft

    Button {
      text: "Copy version details"
      bordered: true
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.copy(root.details, "Version details")
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.notice
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
