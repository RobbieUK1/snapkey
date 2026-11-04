import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Snapkey is a panel plugin with no bar widget. The apps-menu entry calls
// `omarchy-shell shell summon robbie.snapkey`, which opens this window.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var actions: []
  property bool ready: false
  property bool busy: false
  property string errorText: ""
  property string notice: ""
  property bool noticeIsError: false
  property int selectedIndex: 0
  property int recordingIndex: -1
  property bool confirming: false
  property var pending: null
  property var pendingConflict: null
  property bool helpVisible: false

  readonly property string helper: decodeURIComponent(
    Qt.resolvedUrl("snapkey").toString().replace("file://", "")
  )
  readonly property var selectedAction:
    actions.length > 0
      ? actions[Math.max(0, Math.min(selectedIndex, actions.length - 1))]
      : null

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  // ---------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    confirming = false
    pending = null
    pendingConflict = null
    recordingIndex = -1
    helpVisible = false
    notice = ""
    noticeIsError = false
    opened = true
    refresh()
    focusTimer.restart()
  }

  // Host-initiated close (`shell hide`). The window follows `opened`; the
  // host already knows it is closing, so nothing is reported back.
  function close() {
    opened = false
    recordingIndex = -1
    confirming = false
    pending = null
    pendingConflict = null
  }

  // User-initiated close (Esc or the close button). Tell the shell so its
  // openPanelIds map stays consistent.
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("robbie.snapkey")
    else close()
  }

  // Used by `omarchy-shell shell call robbie.snapkey debugState ""` when
  // checking the plugin without looking at the screen.
  function debugState() {
    return JSON.stringify({
      opened: opened,
      windowVisible: window.shown,
      contentRevealed: window.contentRevealed,
      ready: ready,
      busy: busy,
      actionCount: actions.length,
      error: errorText,
      windowWidth: window.width,
      windowHeight: window.height
    })
  }

  // --------------------------------------------------------------- backend IO

  function refresh() {
    if (statusProcess.running) return
    busy = true
    statusProcess.command = [helper, "status"]
    statusProcess.running = true
  }

  function checkAndApply(id, chord) {
    if (checkProcess.running) return
    busy = true
    pending = { id: id, chord: chord }
    checkProcess.command = [helper, "check", id, chord]
    checkProcess.running = true
  }

  function applyPending() {
    if (!pending || setProcess.running) return
    busy = true
    confirming = false
    pendingConflict = null
    setProcess.command = [helper, "set", pending.id, pending.chord]
    setProcess.running = true
  }

  function cancelPending() {
    confirming = false
    pending = null
    pendingConflict = null
  }

  function resetAction(index) {
    if (busy || resetProcess.running) return
    var action = actions[index]
    if (!action || action.source !== "custom") return
    busy = true
    notice = ""
    resetProcess.command = [helper, "reset", action.id]
    resetProcess.running = true
  }

  function parseJson(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      return parsed && typeof parsed === "object" ? parsed : null
    } catch (error) {
      return null
    }
  }

  function handleStatus(raw) {
    busy = false
    var result = parseJson(raw)
    if (!result || result.ok !== true) {
      errorText = result && result.error
        ? String(result.error)
        : strings.t("helperError")
      return
    }
    errorText = ""
    actions = enrich(result.actions || [])
    ready = true
    if (selectedIndex >= actions.length)
      selectedIndex = Math.max(0, actions.length - 1)
    ensureVisible(selectedIndex)
  }

  function handleCheck(raw) {
    busy = false
    var result = parseJson(raw)
    if (!result || result.ok !== true) {
      noticeIsError = true
      notice = result && result.error ? String(result.error) : strings.t("helperError")
      pending = null
      noticeTimer.restart()
      return
    }
    if (!result.conflict) {
      applyPending()
      return
    }
    if (result.conflict.kind === "snapkey") {
      noticeIsError = true
      notice = strings.t("conflictSnapkey")
        .arg(pending ? pending.chord : "")
        .arg(result.conflict.label)
      pending = null
      noticeTimer.restart()
      return
    }
    pendingConflict = result.conflict
    confirming = true
  }

  function handleChange(raw, successMessage) {
    busy = false
    var result = parseJson(raw)
    if (!result || result.ok !== true) {
      noticeIsError = true
      notice = result && result.error ? String(result.error) : strings.t("bindingError")
      noticeTimer.restart()
      refresh()
      return
    }
    actions = enrich(result.actions || [])
    ready = true
    errorText = ""
    pending = null
    pendingConflict = null
    confirming = false
    noticeIsError = false
    notice = successMessage
    noticeTimer.restart()
    ensureVisible(selectedIndex)
  }

  function enrich(list) {
    var enriched = []
    for (var i = 0; i < list.length; i++) {
      var action = list[i]
      var id = String(action.id || "")
      enriched.push({
        id: id,
        label: String(action.label || ""),
        command: String(action.command || ""),
        section: String(action.section || "screenshots"),
        chord: String(action.chord || ""),
        source: String(action.source || ""),
        title: strings.t("action." + id + ".title", String(action.label || "")),
        description: strings.t("action." + id + ".description", ""),
        icon: iconFor(id),
        notSetLabel: strings.t("notSet"),
        customLabel: strings.t("custom"),
        recordingLabel: strings.t("pressKeys"),
        resetLabel: strings.t("reset")
      })
    }
    return enriched
  }

  function iconFor(id) {
    if (id === "smart") return "\uf030"
    if (id === "region") return "\uf125"
    if (id === "window") return "\uf2d0"
    if (id === "fullscreen") return "\uf065"
    if (id === "fullscreen-save") return "\uf0c7"
    if (id === "scroll") return "\uf07d"
    if (id === "text") return "\uf031"
    if (id === "qr") return "\uf029"
    if (id === "menu") return "\uf0c9"
    return "\uf030"
  }

  // ------------------------------------------------------------- key capture

  function isModifierKey(key) {
    return key === Qt.Key_Shift || key === Qt.Key_Control
      || key === Qt.Key_Alt || key === Qt.Key_AltGr
      || key === Qt.Key_Meta || key === Qt.Key_Super_L
      || key === Qt.Key_Super_R || key === Qt.Key_CapsLock
  }

  function keyName(key) {
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    if (key >= Qt.Key_F1 && key <= Qt.Key_F24) return "F" + (key - Qt.Key_F1 + 1)

    switch (key) {
    case Qt.Key_Print: return "PRINT"
    case Qt.Key_SysReq: return "PRINT"
    case Qt.Key_Space: return "SPACE"
    case Qt.Key_Tab: return "TAB"
    case Qt.Key_Return:
    case Qt.Key_Enter: return "RETURN"
    case Qt.Key_Backspace: return "BACKSPACE"
    case Qt.Key_Delete: return "DELETE"
    case Qt.Key_Insert: return "INSERT"
    case Qt.Key_Home: return "HOME"
    case Qt.Key_End: return "END"
    case Qt.Key_PageUp: return "PAGE_UP"
    case Qt.Key_PageDown: return "PAGE_DOWN"
    case Qt.Key_Left: return "LEFT"
    case Qt.Key_Right: return "RIGHT"
    case Qt.Key_Up: return "UP"
    case Qt.Key_Down: return "DOWN"
    case Qt.Key_Pause: return "PAUSE"
    case Qt.Key_ScrollLock: return "SCROLL_LOCK"
    case Qt.Key_NumLock: return "NUM_LOCK"
    case Qt.Key_Menu: return "MENU"
    case Qt.Key_Comma: return "comma"
    case Qt.Key_Period: return "period"
    case Qt.Key_Slash: return "slash"
    case Qt.Key_Backslash: return "backslash"
    case Qt.Key_Minus: return "minus"
    case Qt.Key_Equal: return "equal"
    case Qt.Key_BracketLeft: return "bracketleft"
    case Qt.Key_BracketRight: return "bracketright"
    case Qt.Key_Semicolon: return "semicolon"
    case Qt.Key_Apostrophe: return "apostrophe"
    case Qt.Key_QuoteLeft: return "grave"
    }
    return ""
  }

  function bareKeyAllowed(key) {
    if (key === "PRINT" || key === "PAUSE" || key === "SCROLL_LOCK") return true
    return /^F([1-9]|1[0-9]|2[0-4])$/.test(key)
  }

  function startRecording(index) {
    if (busy || index < 0 || index >= actions.length) return
    confirming = false
    pending = null
    pendingConflict = null
    recordingIndex = index
    selectedIndex = index
    notice = ""
    noticeIsError = false
    keyCatcher.forceActiveFocus()
  }

  function cancelRecording() {
    recordingIndex = -1
    keyCatcher.forceActiveFocus()
  }

  function captureKey(event) {
    if (event.isAutoRepeat) return true

    if (event.key === Qt.Key_Escape) {
      cancelRecording()
      return true
    }
    if (isModifierKey(event.key)) return true

    var key = keyName(event.key)
    if (key === "") {
      noticeIsError = true
      notice = strings.t("unsupportedKey")
      noticeTimer.restart()
      return true
    }

    var mods = []
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")

    if (mods.length === 0 && !bareKeyAllowed(key)) {
      noticeIsError = true
      notice = strings.t("modifierRequired")
      noticeTimer.restart()
      return true
    }

    var chord = mods.concat([key]).join(" + ")
    var action = actions[recordingIndex]
    recordingIndex = -1
    if (action) checkAndApply(action.id, chord)
    return true
  }

  // --------------------------------------------------------------- navigation

  function moveSelection(delta) {
    if (actions.length === 0) return
    selectedIndex = Math.max(0, Math.min(actions.length - 1, selectedIndex + delta))
    ensureVisible(selectedIndex)
  }

  function selectIndex(index) {
    if (actions.length === 0) return
    selectedIndex = Math.max(0, Math.min(actions.length - 1, index))
    ensureVisible(selectedIndex)
  }

  function ensureVisible(index) {
    if (!ready || index < 0) return
    var item = rows.itemAt(index)
    if (!item) return
    var top = item.y
    var bottom = top + item.height
    if (top < flick.contentY) {
      flick.contentY = top
    } else if (bottom > flick.contentY + flick.height) {
      flick.contentY = Math.min(
        Math.max(0, rowsColumn.height - flick.height),
        bottom - flick.height
      )
    }
  }

  // ------------------------------------------------------------------- window

  OverlayWindow {
    id: window
    shown: root.opened
    WlrLayershell.namespace: "omarchy-snapkey"
    onShownChanged: if (shown) focusTimer.restart()

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (root.helpVisible) {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return
              || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
              || event.text === "?") {
            root.helpVisible = false
            event.accepted = true
          }
          return
        }

        if (root.confirming) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
              || event.key === Qt.Key_Y) {
            root.applyPending()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_N) {
            root.cancelPending()
            event.accepted = true
          }
          return
        }

        if (root.recordingIndex >= 0) {
          if (root.captureKey(event)) event.accepted = true
          return
        }

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
          root.requestClose()
          event.accepted = true
          break
        case Qt.Key_Up:
        case Qt.Key_K:
          root.moveSelection(-1)
          event.accepted = true
          break
        case Qt.Key_Down:
        case Qt.Key_J:
          root.moveSelection(1)
          event.accepted = true
          break
        case Qt.Key_Home:
          root.selectIndex(0)
          event.accepted = true
          break
        case Qt.Key_End:
          root.selectIndex(root.actions.length - 1)
          event.accepted = true
          break
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
          root.startRecording(root.selectedIndex)
          event.accepted = true
          break
        case Qt.Key_Delete:
        case Qt.Key_Backspace:
          root.resetAction(root.selectedIndex)
          event.accepted = true
          break
        default:
          if (event.text === "?") {
            root.helpVisible = true
            event.accepted = true
          }
        }
      }

      // Clicking the dimmed desktop dismisses; the card swallows its own
      // clicks so using the panel never closes it.
      Rectangle {
        anchors.fill: parent
        color: Commons.Color.menu.scrim
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.requestClose()
      }

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(Style.space(900), parent.width - Style.space(48))
        height: Math.min(Style.space(860), parent.height - Style.space(48))
        radius: Style.cornerRadius
        color: Commons.Color.popups.background
        border.width: Math.max(1, Style.space(1))
        border.color: Commons.Color.popups.border

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onWheel: function(wheel) { wheel.accepted = false }
        }
      }

      ColumnLayout {
        anchors.centerIn: parent
        width: card.width - Style.spacing.panelPadding * 2
        height: card.height - Style.spacing.panelPadding * 2
        spacing: Style.spacing.panelGap

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              text: strings.t("title")
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
              textFormat: Text.PlainText
            }

            Text {
              Layout.fillWidth: true
              text: strings.t("subtitle")
              color: Commons.Color.popups.text
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
          }

          Button {
            text: "\u2715"
            tooltipText: strings.t("close")
            bordered: false
            foreground: Commons.Color.popups.text
            fontFamily: Style.font.family
            onClicked: root.requestClose()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          implicitHeight: Math.max(1, Style.space(1))
          color: Util.alpha(Commons.Color.foreground, 0.12)
        }

        Text {
          Layout.fillWidth: true
          visible: !root.ready && root.errorText === ""
          text: strings.t("loading")
          color: Commons.Color.popups.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          textFormat: Text.PlainText
        }

        Text {
          Layout.fillWidth: true
          visible: root.errorText !== ""
          text: root.errorText
          color: Commons.Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
        }

        Flickable {
          id: flick
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.ready
          clip: true
          contentWidth: width
          contentHeight: rowsColumn.height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: rowsColumn
            width: flick.width
            spacing: Style.spacing.xs

            Repeater {
              id: rows
              model: root.actions

              delegate: Column {
                id: rowBlock
                required property var modelData
                required property int index

                width: rowsColumn.width
                spacing: Style.spacing.xs

                Text {
                  visible: rowBlock.index === 0
                    || root.actions[rowBlock.index - 1].section !== rowBlock.modelData.section
                  width: parent.width
                  topPadding: rowBlock.index === 0 ? 0 : Style.spacing.md
                  text: rowBlock.modelData.section === "more"
                    ? strings.t("section.more")
                    : strings.t("section.screenshots")
                  color: Commons.Color.popups.text
                  opacity: 0.55
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  textFormat: Text.PlainText
                }

                ActionRow {
                  width: rowBlock.width
                  action: rowBlock.modelData
                  selected: root.selectedIndex === rowBlock.index
                  recording: root.recordingIndex === rowBlock.index
                  busy: root.busy
                  onActivated: root.startRecording(rowBlock.index)
                  onResetRequested: root.resetAction(rowBlock.index)
                  onHovered: root.selectedIndex = rowBlock.index
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          visible: root.confirming
          implicitHeight: conflictColumn.implicitHeight + Style.spacing.controlPaddingY * 2
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.urgent, 0.12)
          border.width: Math.max(1, Style.space(1))
          border.color: Util.alpha(Commons.Color.urgent, 0.55)

          ColumnLayout {
            id: conflictColumn
            anchors.fill: parent
            anchors.margins: Style.spacing.controlPaddingX
            spacing: Style.spacing.xs

            Text {
              Layout.fillWidth: true
              text: strings.t("conflictTitle")
              color: Commons.Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              textFormat: Text.PlainText
            }

            Text {
              Layout.fillWidth: true
              text: strings.t("conflictBody")
                .arg(root.pending ? root.pending.chord : "")
                .arg(root.pendingConflict ? root.pendingConflict.label : "")
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.sm

              Button {
                text: strings.t("replace")
                bordered: true
                foreground: Commons.Color.urgent
                fontFamily: Style.font.family
                onClicked: root.applyPending()
              }

              Button {
                text: strings.t("cancel")
                bordered: true
                foreground: Commons.Color.popups.text
                fontFamily: Style.font.family
                onClicked: root.cancelPending()
              }

              Item { Layout.fillWidth: true }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.notice !== ""
          text: root.notice
          color: root.noticeIsError ? Commons.Color.urgent : Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md

          Text {
            Layout.fillWidth: true
            text: root.busy
              ? strings.t("working")
              : strings.t("hints")
            color: Commons.Color.popups.text
            opacity: 0.45
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }

          Text {
            visible: root.ready
            text: strings.t("bindingsFile").arg("~/.config/hypr/bindings.lua")
            color: Commons.Color.popups.text
            opacity: 0.32
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }

      // Help overlay covers the card with the same surface and lists every
      // shortcut.
      Rectangle {
        anchors.fill: card
        radius: card.radius
        visible: root.helpVisible
        color: Commons.Color.popups.background

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.sm

          Text {
            Layout.fillWidth: true
            text: strings.t("help.title")
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
          }

          Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: strings.t("help.body")
            color: Commons.Color.popups.text
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            lineHeight: 1.5
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }

          Text {
            Layout.fillWidth: true
            text: strings.t("help.close")
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.helpVisible = false
        }
      }

      Timer {
        id: focusTimer
        interval: 90
        onTriggered: {
          if (root.opened) {
            keyCatcher.forceActiveFocus()
            root.ensureVisible(root.selectedIndex)
          }
        }
      }

      Timer {
        id: noticeTimer
        interval: 4200
        onTriggered: {
          root.notice = ""
          root.noticeIsError = false
        }
      }
    }
  }

  // ---------------------------------------------------------------- processes

  Process {
    id: statusProcess
    command: [root.helper, "status"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleStatus(text)
    }
  }

  Process {
    id: checkProcess
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleCheck(text)
    }
  }

  Process {
    id: setProcess
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleChange(text, strings.t("saved"))
    }
  }

  Process {
    id: resetProcess
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleChange(text, strings.t("resetDone"))
    }
  }
}
