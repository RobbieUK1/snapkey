import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One screenshot action: what it does, its current key, and a reset control.
// The parent owns the keyboard cursor and key capture; this file only paints
// the row and reports clicks.
Rectangle {
  id: row

  required property var action
  property bool selected: false
  property bool recording: false
  property bool busy: false

  signal activated()
  signal resetRequested()
  signal hovered()

  readonly property bool custom: action.source === "custom"
  readonly property string chord: String(action.chord || "")

  implicitHeight: Math.max(Style.space(54), content.implicitHeight + Style.spacing.sm * 2)
  radius: Style.cornerRadius
  color: recording
    ? Util.alpha(Commons.Color.accent, 0.14)
    : selected
      ? Commons.Color.menu.selectedBackground
      : hover.containsMouse
        ? Util.alpha(Commons.Color.foreground, 0.05)
        : "transparent"
  border.width: recording || selected ? Math.max(1, Style.space(1)) : 0
  border.color: recording ? Commons.Color.accent : Commons.Color.menu.selectedBorder

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.hovered()
    onClicked: {
      row.hovered()
      if (!row.busy) row.activated()
    }
  }

  RowLayout {
    id: content
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    spacing: Style.spacing.rowGap

    Text {
      Layout.preferredWidth: Style.space(26)
      text: row.action.icon || ""
      color: row.recording ? Commons.Color.accent : Commons.Color.popups.text
      opacity: row.recording ? 1 : 0.78
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.sm

        Text {
          text: row.action.title || ""
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Rectangle {
          visible: row.custom
          implicitWidth: customLabel.implicitWidth + Style.spacing.sm * 2
          implicitHeight: customLabel.implicitHeight + Style.space(2)
          radius: Math.min(Style.space(4), Style.cornerRadius)
          color: Util.alpha(Commons.Color.accent, 0.16)

          Text {
            id: customLabel
            anchors.centerIn: parent
            text: row.action.customLabel || "Custom"
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: row.action.description || ""
        color: Commons.Color.popups.text
        opacity: 0.58
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
    }

    Rectangle {
      id: keyPill
      implicitWidth: Math.max(
        Style.space(132),
        keyLabel.implicitWidth + Style.spacing.controlPaddingX * 2
      )
      implicitHeight: Style.spacing.controlHeight
      radius: Math.min(Style.space(6), Style.cornerRadius)
      color: row.recording
        ? Util.alpha(Commons.Color.accent, 0.22)
        : row.chord !== ""
          ? Util.alpha(Commons.Color.foreground, 0.07)
          : "transparent"
      border.width: Math.max(1, Style.space(1))
      border.color: row.recording
        ? Commons.Color.accent
        : Util.alpha(Commons.Color.foreground, row.chord !== "" ? 0.22 : 0.14)

      Text {
        id: keyLabel
        anchors.centerIn: parent
        width: parent.width - Style.spacing.controlPaddingX * 2
        text: row.recording
          ? (row.action.recordingLabel || "Press keys…")
          : row.chord !== ""
            ? row.chord
            : (row.action.notSetLabel || "Not set")
        color: Commons.Color.popups.text
        opacity: row.chord !== "" || row.recording ? 1 : 0.45
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.weight: row.chord !== "" ? Font.DemiBold : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          row.hovered()
          if (!row.busy) row.activated()
        }
      }
    }

    Button {
      visible: row.custom && !row.recording
      text: "\u2715"
      tooltipText: row.action.resetLabel || "Reset"
      bordered: false
      foreground: Commons.Color.popups.text
      fontFamily: Style.font.family
      fontSize: Style.font.bodySmall
      enabled: !row.busy
      onClicked: row.resetRequested()
    }
  }
}
