import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.lightning-balance"

  property string balance: ""
  property bool ok: false

  function refresh() {
    if (!balanceProc.running) balanceProc.running = true
  }

  function formatSats(n) {
    // Group thousands so a big balance stays readable: 1234567 -> 1 234 567
    var s = String(n)
    return s.replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  }

  // Hide entirely until a balance has been read, so a missing or misconfigured
  // wallet leaves no dead icon in the bar.
  visible: ok && balance !== "" && !vertical
  implicitWidth: visible ? row.implicitWidth + Style.space(16) : 0
  implicitHeight: barSize

  ShellIpc {
    target: "omarchy.lightning-balance"
    function refresh(): void { root.broadcast("refresh") }
  }

  Process {
    id: balanceProc
    command: ["omarchy-lightning-balance"]
    stdout: StdioCollector { id: out }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var v = out.text.trim()
        if (v.length > 0 && /^[0-9]+$/.test(v)) {
          root.balance = root.formatSats(v)
          root.ok = true
          return
        }
      }
      root.ok = false
      root.balance = ""
    }
  }

  // Refresh every 2 minutes. A balance does not need to be to-the-second.
  Timer {
    interval: 120000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "₿"   // bitcoin sign
      color: root.bar ? root.bar.barForeground : Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.balance
      color: root.bar ? root.bar.barForeground : Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.refresh()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.balance + " sats  (click to refresh)")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
