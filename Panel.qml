import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Canari's beacon: pulses red while a Hermes agent is waiting for an
// approval decision. The hook script (~/.hermes/agent-hooks/attention.sh)
// owns the state file and is its only writer; this widget only reads.
// Left-click: panel with the flagged command. Right-click: silence.
Panel {
  id: root
  moduleName: "bakugo.hermes-attention"
  ipcTarget: "bakugo.hermes-attention"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string stateDir: Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")

  property var state: null
  readonly property bool pending: !!state && state.pending === true
  readonly property int count: state && state.count > 0 ? state.count : 0
  readonly property int sinceEpoch: state && state.since > 0 ? state.since : 0
  readonly property string sinceIso: {
    if (!sinceEpoch) return ""
    var d = new Date(sinceEpoch * 1000)
    return isNaN(d.getTime()) ? "" : d.toTimeString().substr(0, 8)
  }
  readonly property string waitingFor: {
    if (!state) return ""
    var parts = []
    if (state.description) parts.push(String(state.description))
    if (state.patternKeys) parts.push("[" + String(state.patternKeys) + "]")
    return parts.join(" · ")
  }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function silence() {
    Quickshell.execDetached(["/home/bakugo/.hermes/agent-hooks/attention.sh", "--clear"])
  }

  onOpenedChanged: if (opened) {
    stateFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Fresh prompt = still alive: every new `since` restarts the stale timer.
  onSinceEpochChanged: if (pending) staleTimer.restart()

  // Self-hiding like the stock agents widget: no state file ever read
  // means nothing has needed attention yet - collapse the slot entirely.
  visible: stateFile.loaded
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: stateFile
    path: root.stateDir + "/hermes-attention/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: root.state = null
  }

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.state = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.state = null
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function silence(): void { root.silence() }
    function refresh(): string { stateFile.reload(); return "ok" }
  }

  // ---- bar chip -----------------------------------------------------------

  BorderSurface {
    id: chipBackdrop
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: Style.space(18)
    radius: Math.min(Style.cornerRadius, height / 2)
    color: root.pending ? root.alpha(root.urgent, 0.22) : root.alpha(root.foreground, 0.06)
    borderSpec: Border.flat(
      root.pending ? root.urgent : root.alpha(root.foreground, 0.35), 1)

    // The chip breathes while an approval is pending.
    SequentialAnimation on opacity {
      running: root.pending
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.45; duration: 650; easing.type: Easing.InOutQuad }
      NumberAnimation { from: 0.45; to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pending ? (root.count > 1 ? "×" + root.count : "!") : "✓"
    foreground: root.pending ? root.urgent : root.dim
    active: false
    fontSize: Style.font.caption
    horizontalMargin: 7
    verticalPadding: 5
    tooltipText: root.pending
      ? "Canari needs your approval" + (root.count > 1 ? " (" + root.count + " waiting)" : "")
        + (root.waitingFor !== "" ? "\n" + root.waitingFor : "")
      : "Hermes approvals: all clear"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.silence()
      else root.toggle()
    }
  }

  // ---- stale guard ----------------------------------------------------------
  // If no fresh prompt arrived in staleMin minutes, the session that raised
  // the alert is probably dead (terminal closed mid-prompt). Stop pulsing;
  // the next prompt re-arms everything.
  Timer {
    id: staleTimer
    interval: Math.max(1, Number(root.setting("staleMin", 30))) * 60000
    running: root.pending
    repeat: false
    onTriggered: root.silence()
  }

  // ---- click panel ---------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.silence()
        if (t === "r" || t === "R") stateFile.reload()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Hermes Attention"
            meta: root.pending ? "WAITING ON YOU" : "All clear"
            detail: root.pending && root.count > 1 ? root.count + " stacked" : ""
            foreground: root.pending ? root.urgent : root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                BorderSurface {
                  anchors.fill: parent
                  radius: Math.min(Style.cornerRadius, height / 2)
                  color: root.pending ? root.alpha(root.urgent, 0.22) : root.alpha(root.foreground, 0.06)
                  borderSpec: Border.flat(
                    root.pending ? root.urgent : root.alpha(root.foreground, 0.35), 1)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.pending ? "!" : "✓"
                    color: root.pending ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(Style.font.display * 0.62)
                  }
                }
              }
            }
          }

          // ---------- Command card ----------
          BorderSurface {
            visible: root.pending
            width: parent.width
            implicitHeight: cmdText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.45), 1)
            radius: Style.cornerRadius

            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                visible: root.waitingFor !== ""
                width: parent.width
                text: root.waitingFor
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                id: cmdText
                textFormat: Text.PlainText
                width: parent.width
                text: root.state && root.state.command ? String(root.state.command) : ""
                color: root.foreground
                font.family: "monospace"
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WrapAnywhere
              }

              Text {
                textFormat: Text.PlainText
                visible: root.sinceIso !== ""
                width: parent.width
                text: "waiting since " + root.sinceIso + " · session "
                  + (root.state && root.state.sessionKey ? String(root.state.sessionKey) : "?")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          // ---------- All-clear card ----------
          BorderSurface {
            visible: !root.pending
            width: parent.width
            implicitHeight: clearText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.foreground, 0.06)
            borderSpec: Border.flat(root.alpha(root.foreground, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: clearText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: "No approval prompts pending.\nWhen Canari needs permission, the bar chip pulses red and a critical toast pops on screen."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Footer ----------
          Text {
            textFormat: Text.PlainText
            width: parent.width
            topPadding: Style.space(2)
            text: "Left-click chip: this panel · Right-click chip: silence · S here: silence · R: refresh\nThe toast stays on screen until you answer it."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
