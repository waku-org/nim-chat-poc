import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: root
    visible: true
    width: 1100
    height: 720
    color: "#0A0A0A"

    // Dynamic title
    title: {
        var nodes = 0
        try { var n = JSON.parse(monitor.mixNodeStates); nodes = n.filter(function(x){return x.lez && x.kad}).length } catch(e){}
        var s = "Sim Monitor"
        if (monitor.blockId > 0) s += " — block " + monitor.blockId
        s += " | " + nodes + "/4 nodes"
        if (monitor.senderPhase !== "---") s += " | S:" + monitor.senderPhase
        if (monitor.receiverPhase !== "---") s += " | R:" + monitor.receiverPhase
        return s
    }

    readonly property color bgPrimary:   "#0A0A0A"
    readonly property color bgSecondary: "#111111"
    readonly property color bgPanel:     "#161616"
    readonly property color border:      "#2a2a2a"
    readonly property color textPrimary: "#FAFAFA"
    readonly property color textSecond:  "#6B7280"
    readonly property color textTertiary:"#4B5563"
    readonly property color accent:      "#10B981"
    readonly property color accentDim:   "#065F46"
    readonly property color yellow:      "#F59E0B"
    readonly property color red:         "#EF4444"
    readonly property color blue:        "#2563EB"

    readonly property string monoFont: "JetBrains Mono, Menlo, Monaco, monospace"

    function nodeColor(jsonStr, idx) {
        try {
            var nodes = JSON.parse(jsonStr)
            var n = nodes[idx]
            if (n.lez && n.kad) return accent
            if (n.mounted) return yellow
        } catch(e) {}
        return textTertiary
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        // ═══════════════════════════════════════════════════════════
        // INFRA: Sequencer heartbeat + Network topology + Gifter
        // ═══════════════════════════════════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 130
            color: bgSecondary
            radius: 6

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 20

                // ── Sequencer heartbeat ──
                ColumnLayout {
                    Layout.preferredWidth: 180
                    spacing: 4

                    RowLayout {
                        spacing: 6
                        // Pulsing heartbeat dot
                        Rectangle {
                            id: heartbeat
                            width: 12; height: 12; radius: 6
                            color: monitor.blockId > 0 ? root.accent : root.textTertiary

                            SequentialAnimation on scale {
                                id: heartbeatAnim
                                loops: 1
                                NumberAnimation { to: 1.4; duration: 100; easing.type: Easing.OutQuad }
                                NumberAnimation { to: 1.0; duration: 300; easing.type: Easing.InQuad }
                            }
                            property int _lastBlock: 0
                            Connections {
                                target: monitor
                                function onStateChanged() {
                                    if (monitor.blockId !== heartbeat._lastBlock && monitor.blockId > 0) {
                                        heartbeatAnim.restart()
                                        heartbeat._lastBlock = monitor.blockId
                                    }
                                }
                            }
                        }
                        Text {
                            font.family: root.monoFont; font.pixelSize: 11; font.bold: true
                            color: root.textSecond
                            text: "SEQUENCER"
                        }
                    }

                    // Block number (large)
                    Text {
                        font.family: root.monoFont; font.pixelSize: 28; font.bold: true
                        color: root.textPrimary
                        text: monitor.blockId > 0 ? "# " + monitor.blockId : "---"
                    }

                    // Block age bar
                    Rectangle {
                        Layout.fillWidth: true; height: 4; radius: 2; color: root.border
                        Rectangle {
                            width: {
                                var age = monitor.blockAgeSecs
                                if (age < 0) return 0
                                return Math.min(1.0, age / 30.0) * parent.width
                            }
                            height: parent.height; radius: 2
                            color: {
                                var age = monitor.blockAgeSecs
                                if (age < 15) return root.accent
                                if (age < 30) return root.yellow
                                return root.red
                            }
                        }
                    }

                    // TX counters
                    Text {
                        font.family: root.monoFont; font.pixelSize: 10
                        color: root.textSecond
                        text: "tx: " + monitor.txValidated + " ✓  " + monitor.txFailed + " ✗" +
                              (monitor.rpcReachable ? "  rpc:" + monitor.rpcBlockId : "")
                    }
                }

                // ── Separator ──
                Rectangle { width: 1; Layout.fillHeight: true; color: root.border }

                // ── Network topology (horizontal) ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text { font.family: root.monoFont; font.pixelSize: 11; font.bold: true; color: root.textSecond; text: "MIX NETWORK"; Layout.alignment: Qt.AlignHCenter }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        Repeater {
                            model: 4
                            Column {
                                spacing: 3
                                Rectangle {
                                    width: 44; height: 44; radius: 22
                                    color: nodeColor(monitor.mixNodeStates, index)
                                    border.color: Qt.lighter(nodeColor(monitor.mixNodeStates, index), 1.3)
                                    border.width: 2
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        font.family: root.monoFont; font.pixelSize: 13; font.bold: true
                                        color: "#000"
                                        text: "N" + index
                                    }
                                }
                                Rectangle {
                                    visible: index === 0
                                    width: giftLabel.implicitWidth + 8; height: 14; radius: 4
                                    color: monitor.gifterMounted ? root.accent : root.textTertiary
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Text {
                                        id: giftLabel
                                        anchors.centerIn: parent
                                        font.family: root.monoFont; font.pixelSize: 8; font.bold: true
                                        color: "#000"
                                        text: "GIFTER"
                                    }
                                }
                                Text {
                                    visible: index !== 0
                                    font.family: root.monoFont; font.pixelSize: 8
                                    color: root.textTertiary
                                    text: "relay"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }

                    // Connection line under the nodes
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 4 * 44 + 3 * 12; height: 2; radius: 1
                        color: {
                            try {
                                var nodes = JSON.parse(monitor.mixNodeStates)
                                var allGreen = nodes.every(function(n) { return n.lez && n.kad })
                                if (allGreen) return root.accent
                                var anyMounted = nodes.some(function(n) { return n.mounted })
                                if (anyMounted) return root.yellow
                            } catch(e) {}
                            return root.border
                        }
                    }
                }

                // ── Separator ──
                Rectangle { width: 1; Layout.fillHeight: true; color: root.border }

                // ── Gifter stats ──
                ColumnLayout {
                    Layout.preferredWidth: 100
                    spacing: 4
                    Text { font.family: root.monoFont; font.pixelSize: 11; font.bold: true; color: root.textSecond; text: "GIFTER" }
                    Text { font.family: root.monoFont; font.pixelSize: 10; color: root.accent; text: "✓ " + (monitor.gifterMounted ? "mounted" : "---") }
                    Text { font.family: root.monoFont; font.pixelSize: 10; color: root.textSecond; text: "queue: " + monitor.gifterQueueDepth }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        // MESSAGE FLOW: Sender ──→ ←── Receiver
        // ═══════════════════════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Sender panel ──
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: bgSecondary
                radius: 6
                clip: true

                property string role: "sender"
                property string phase: monitor.senderPhase
                property int optLeaf: monitor.senderOptLeaf
                property int authLeaf: monitor.senderAuthLeaf
                property bool corrected: monitor.senderLeafCorrected
                property int peers: monitor.senderPeers
                property bool mixRdy: monitor.senderMixReady
                property int pool: monitor.senderMixPool
                property int out_: monitor.senderMsgOut
                property int in_: monitor.senderMsgIn

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Header
                    RowLayout {
                        spacing: 8
                        Text { font.family: root.monoFont; font.pixelSize: 16; font.bold: true; color: root.textPrimary; text: "SENDER" }
                        Rectangle {
                            width: sLabel.implicitWidth + 12; height: 20; radius: 10
                            color: monitor.senderPhase === "---" ? root.textTertiary :
                                   (monitor.senderPhase === "msg_sent" ? root.accent :
                                   (monitor.senderPhase.indexOf("conf") >= 0 ? root.blue : root.yellow))
                            Text { id: sLabel; anchors.centerIn: parent; font.family: root.monoFont; font.pixelSize: 9; font.bold: true; color: "#FFF"
                                text: monitor.senderPhase === "---" ? "WAITING" : monitor.senderPhase.toUpperCase() }
                        }
                    }

                    // Phase timeline
                    Row {
                        spacing: 0
                        Repeater {
                            model: ["init", "start", "reg", "opt", "conf", "ready", "intro", "send"]
                            Row {
                                spacing: 0
                                property var allPhases: ["init", "start", "request", "opt", "conf", "ready", "intro_emitted", "msg_sent"]
                                property int currentIdx: allPhases.indexOf(monitor.senderPhase.split(":")[0])
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: index < currentIdx ? root.accent : (index === currentIdx ? root.yellow : root.border)
                                    border.color: index <= currentIdx ? Qt.lighter(color, 1.3) : "transparent"; border.width: 1
                                    scale: index === currentIdx ? 1.3 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200 } }
                                }
                                Rectangle {
                                    visible: index < 7
                                    width: 16; height: 2; color: index < currentIdx ? root.accent : root.border
                                    anchors.verticalCenter: parent.children[0].verticalCenter
                                }
                            }
                        }
                    }

                    // RLN + Network
                    Text { font.family: root.monoFont; font.pixelSize: 10; color: parent.parent.corrected ? root.yellow : (parent.parent.optLeaf >= 0 && parent.parent.optLeaf === parent.parent.authLeaf ? root.accent : root.textSecond)
                        text: "RLN " + (parent.parent.authLeaf >= 0 ? "leaf " + parent.parent.authLeaf + " ✓" : (parent.parent.optLeaf >= 0 ? "leaf " + parent.parent.optLeaf + " ⏳" : "not registered")) }
                    Text { font.family: root.monoFont; font.pixelSize: 10; color: parent.parent.mixRdy ? root.accent : root.textSecond
                        text: "NET " + parent.parent.peers + " peers" + (parent.parent.mixRdy ? " · mix ✓ pool " + parent.parent.pool : "") }

                    Item { Layout.fillHeight: true }
                }
            }

            // ── Message flow arrows (large, central) ──
            Item {
                Layout.preferredWidth: 80
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    // Sent count (large)
                    Text {
                        font.family: root.monoFont; font.pixelSize: 24; font.bold: true
                        color: monitor.senderMsgOut > 0 ? root.accent : root.textTertiary
                        text: monitor.senderMsgOut > 0 ? String(monitor.senderMsgOut) : "0"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        font.family: root.monoFont; font.pixelSize: 10; color: root.textSecond
                        text: "SENT →"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Separator
                    Rectangle { width: 40; height: 1; color: root.border; Layout.alignment: Qt.AlignHCenter }

                    // Received count (large)
                    Text {
                        font.family: root.monoFont; font.pixelSize: 24; font.bold: true
                        color: monitor.receiverMsgIn > 0 ? root.accent : root.textTertiary
                        text: monitor.receiverMsgIn > 0 ? String(monitor.receiverMsgIn) : "0"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        font.family: root.monoFont; font.pixelSize: 10; color: root.textSecond
                        text: "← RECV"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Separator
                    Rectangle { width: 40; height: 1; color: root.border; Layout.alignment: Qt.AlignHCenter }

                    // Reply count
                    Text {
                        font.family: root.monoFont; font.pixelSize: 16; font.bold: true
                        color: monitor.senderMsgIn > 0 ? root.blue : root.textTertiary
                        text: monitor.senderMsgIn > 0 ? String(monitor.senderMsgIn) : "0"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        font.family: root.monoFont; font.pixelSize: 9; color: root.textSecond
                        text: "← REPLY"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // ── Receiver panel ──
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: bgSecondary
                radius: 6
                clip: true

                property string role: "receiver"
                property string phase: monitor.receiverPhase
                property int optLeaf: monitor.receiverOptLeaf
                property int authLeaf: monitor.receiverAuthLeaf
                property bool corrected: monitor.receiverLeafCorrected
                property int peers: monitor.receiverPeers
                property bool mixRdy: monitor.receiverMixReady
                property int pool: monitor.receiverMixPool
                property int out_: monitor.receiverMsgOut
                property int in_: monitor.receiverMsgIn

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        Text { font.family: root.monoFont; font.pixelSize: 16; font.bold: true; color: root.textPrimary; text: "RECEIVER" }
                        Rectangle {
                            width: rLabel.implicitWidth + 12; height: 20; radius: 10
                            color: monitor.receiverPhase === "---" ? root.textTertiary :
                                   (monitor.receiverPhase === "msg_received" ? root.accent :
                                   (monitor.receiverPhase.indexOf("conf") >= 0 ? root.blue : root.yellow))
                            Text { id: rLabel; anchors.centerIn: parent; font.family: root.monoFont; font.pixelSize: 9; font.bold: true; color: "#FFF"
                                text: monitor.receiverPhase === "---" ? "WAITING" : monitor.receiverPhase.toUpperCase() }
                        }
                    }

                    Row {
                        spacing: 0
                        Repeater {
                            model: ["init", "start", "reg", "opt", "conf", "ready", "accept", "recv"]
                            Row {
                                spacing: 0
                                property var allPhases: ["init", "start", "request", "opt", "conf", "ready", "intro_accepted", "msg_received"]
                                property int currentIdx: allPhases.indexOf(monitor.receiverPhase.split(":")[0])
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: index < currentIdx ? root.accent : (index === currentIdx ? root.yellow : root.border)
                                    border.color: index <= currentIdx ? Qt.lighter(color, 1.3) : "transparent"; border.width: 1
                                    scale: index === currentIdx ? 1.3 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200 } }
                                }
                                Rectangle {
                                    visible: index < 7
                                    width: 16; height: 2; color: index < currentIdx ? root.accent : root.border
                                    anchors.verticalCenter: parent.children[0].verticalCenter
                                }
                            }
                        }
                    }

                    Text { font.family: root.monoFont; font.pixelSize: 10; color: parent.parent.corrected ? root.yellow : (parent.parent.optLeaf >= 0 && parent.parent.optLeaf === parent.parent.authLeaf ? root.accent : root.textSecond)
                        text: "RLN " + (parent.parent.authLeaf >= 0 ? "leaf " + parent.parent.authLeaf + " ✓" : (parent.parent.optLeaf >= 0 ? "leaf " + parent.parent.optLeaf + " ⏳" : "not registered")) }
                    Text { font.family: root.monoFont; font.pixelSize: 10; color: parent.parent.mixRdy ? root.accent : root.textSecond
                        text: "NET " + parent.parent.peers + " peers" + (parent.parent.mixRdy ? " · mix ✓ pool " + parent.parent.pool : "") }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        // CHAIN EVENTS (with icons)
        // ═══════════════════════════════════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 160
            color: bgSecondary
            radius: 6

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Text { font.family: root.monoFont; font.pixelSize: 11; font.bold: true; color: root.textSecond; text: "CHAIN EVENTS" }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: chainEvents
                    clip: true
                    spacing: 1

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 16
                        color: "transparent"
                        radius: 2

                        // Brief flash on new events
                        Rectangle {
                            anchors.fill: parent; radius: 2; color: root.accent; opacity: flashAnim.running ? 0.15 : 0
                            SequentialAnimation on opacity { id: flashAnim; running: index === 0; loops: 1
                                NumberAnimation { to: 0.2; duration: 100 }
                                NumberAnimation { to: 0; duration: 500 }
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            // Icon
                            Text {
                                font.pixelSize: 10
                                text: {
                                    if (eventType === "TX_OK") return "✓"
                                    if (eventType === "TX_FAIL" || eventType === "WALLET_ERR" || eventType === "REG_FAIL") return "✗"
                                    if (eventType === "REGISTER" || eventType === "GIFTER_REQ") return "◆"
                                    if (eventType === "ROOTS") return "◈"
                                    if (eventType === "BUNDLE") return "◉"
                                    if (eventType === "LEAF_FIX") return "⚠"
                                    if (eventType === "GIFTER_AUTHFAIL") return "⛔"
                                    return "·"
                                }
                                color: {
                                    if (eventType === "TX_FAIL" || eventType === "WALLET_ERR" || eventType === "REG_FAIL" || eventType === "GIFTER_AUTHFAIL") return root.red
                                    if (eventType === "REGISTER") return root.accent
                                    if (eventType === "LEAF_FIX") return root.yellow
                                    if (eventType === "BUNDLE") return root.blue
                                    return root.textTertiary
                                }
                            }

                            Text {
                                font.family: root.monoFont; font.pixelSize: 10
                                color: root.textTertiary
                                text: timestamp
                            }
                            Text {
                                font.family: root.monoFont; font.pixelSize: 10; font.bold: true
                                color: {
                                    if (eventType === "TX_FAIL" || eventType === "WALLET_ERR" || eventType === "REG_FAIL") return root.red
                                    if (eventType === "REGISTER") return root.accent
                                    if (eventType === "LEAF_FIX") return root.yellow
                                    return root.textSecond
                                }
                                text: eventType
                            }
                            Text {
                                font.family: root.monoFont; font.pixelSize: 10
                                color: root.textSecond
                                text: detail
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
