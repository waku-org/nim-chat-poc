import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: root
    visible: true
    width: 900
    height: 600
    title: "Sim Monitor"
    color: "#0A0A0A"

    readonly property color bgPrimary:   "#0A0A0A"
    readonly property color bgSecondary: "#111111"
    readonly property color bgPanel:     "#161616"
    readonly property color border:      "#2a2a2a"
    readonly property color textPrimary: "#FAFAFA"
    readonly property color textSecond:  "#6B7280"
    readonly property color textTertiary:"#4B5563"
    readonly property color accent:      "#10B981"
    readonly property color yellow:      "#F59E0B"
    readonly property color red:         "#EF4444"

    readonly property string monoFont: "JetBrains Mono, Menlo, Monaco, monospace"

    function blockAgeColor(secs) {
        if (secs < 0) return textTertiary
        if (secs < 15) return accent
        if (secs < 30) return yellow
        return red
    }

    function mixDotColor(jsonStr) {
        try {
            var nodes = JSON.parse(jsonStr)
            return nodes.map(function(n) {
                if (n.lez && n.kad) return accent
                if (n.mounted) return yellow
                return textTertiary
            })
        } catch(e) {
            return [textTertiary, textTertiary, textTertiary, textTertiary]
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // ─── INFRA STRIP ───────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: bgSecondary
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                // Line 1: Sequencer
                Text {
                    font.family: root.monoFont
                    font.pixelSize: 12
                    color: textPrimary
                    text: {
                        var age = monitor.blockAgeSecs
                        var ageStr = age < 0 ? "---" : age + "s ago"
                        var rpc = monitor.rpcReachable ? " rpc=" + monitor.rpcBlockId : ""
                        return "SEQ block=" + monitor.blockId + " (" + ageStr + rpc + ") tx:" +
                               monitor.txValidated + "✓/" + monitor.txFailed + "✗"
                    }
                }

                // Line 2: Mix dots + Gifter + Payment
                Row {
                    spacing: 16

                    Row {
                        spacing: 2
                        Text { font.family: root.monoFont; font.pixelSize: 12; color: textSecond; text: "MIX " }
                        Repeater {
                            model: 4
                            Text {
                                font.pixelSize: 14
                                text: "●"
                                color: {
                                    var colors = mixDotColor(monitor.mixNodeStates)
                                    return colors[index] || textTertiary
                                }
                            }
                        }
                    }

                    Text {
                        font.family: root.monoFont; font.pixelSize: 12
                        color: monitor.gifterMounted ? accent : textTertiary
                        text: "GIFTER " + monitor.gifterStatus
                    }
                }
            }
        }

        // ─── CHAT PANELS ───────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            Repeater {
                model: ["sender", "receiver"]

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: bgSecondary
                    radius: 4

                    property string role: modelData
                    property string phase: role === "sender" ? monitor.senderPhase : monitor.receiverPhase
                    property int optLeaf: role === "sender" ? monitor.senderOptLeaf : monitor.receiverOptLeaf
                    property int authLeaf: role === "sender" ? monitor.senderAuthLeaf : monitor.receiverAuthLeaf
                    property bool corrected: role === "sender" ? monitor.senderLeafCorrected : monitor.receiverLeafCorrected
                    property int peers: role === "sender" ? monitor.senderPeers : monitor.receiverPeers
                    property bool mixRdy: role === "sender" ? monitor.senderMixReady : monitor.receiverMixReady
                    property int pool: role === "sender" ? monitor.senderMixPool : monitor.receiverMixPool
                    property int out_: role === "sender" ? monitor.senderMsgOut : monitor.receiverMsgOut
                    property int in_: role === "sender" ? monitor.senderMsgIn : monitor.receiverMsgIn

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        // Header + status summary
                        RowLayout {
                            spacing: 8
                            Text {
                                font.family: root.monoFont; font.pixelSize: 14; font.bold: true
                                color: textPrimary
                                text: role.toUpperCase()
                            }
                            Rectangle {
                                width: statusLabel.implicitWidth + 12; height: 18; radius: 9
                                color: {
                                    if (phase === "---") return root.textTertiary
                                    if (phase === "msg_sent" || phase === "msg_received") return root.accent
                                    if (phase.indexOf("conf") >= 0 || phase === "ready" ||
                                        phase === "intro_emitted" || phase === "intro_accepted") return "#2563EB"
                                    return root.yellow
                                }
                                Text {
                                    id: statusLabel
                                    anchors.centerIn: parent
                                    font.family: root.monoFont; font.pixelSize: 9; font.bold: true
                                    color: "#FFF"
                                    text: {
                                        if (phase === "---") return "WAITING"
                                        if (phase === "init") return "INITIALIZED"
                                        if (phase === "start") return "STARTED"
                                        if (phase === "request") return "REGISTERING"
                                        if (phase.indexOf("opt:") >= 0) return "LEAF " + optLeaf + " (OPTIMISTIC)"
                                        if (phase.indexOf("conf:") >= 0) return "LEAF " + authLeaf + " (CONFIRMED)"
                                        if (phase === "ready") return "MIX READY"
                                        if (phase === "intro_emitted") return "BUNDLE CREATED"
                                        if (phase === "intro_accepted") return "BUNDLE ACCEPTED"
                                        if (phase === "msg_sent") return "SENDING"
                                        if (phase === "msg_received") return "RECEIVING"
                                        return phase.toUpperCase()
                                    }
                                }
                            }
                        }

                        // Phase progression bar
                        Row {
                            spacing: 2
                            Repeater {
                                model: ["init", "start", "request", "opt", "conf", "ready",
                                    role === "sender" ? "intro" : "accept",
                                    role === "sender" ? "send" : "recv"]
                                Rectangle {
                                    width: 8; height: 4; radius: 2
                                    color: {
                                        var allPhases = ["init", "start", "request", "opt", "conf", "ready",
                                            role === "sender" ? "intro_emitted" : "intro_accepted",
                                            role === "sender" ? "msg_sent" : "msg_received"]
                                        var current = phase.split(":")[0]
                                        var currentIdx = allPhases.indexOf(current)
                                        if (index < currentIdx) return root.accent
                                        if (index === currentIdx) return root.yellow
                                        return root.border
                                    }
                                }
                            }
                        }

                        // Leaf + membership info
                        RowLayout {
                            spacing: 8
                            Text {
                                font.family: root.monoFont; font.pixelSize: 10
                                color: textSecond
                                text: "RLN MEMBERSHIP"
                            }
                            Text {
                                font.family: root.monoFont; font.pixelSize: 10
                                color: corrected ? root.yellow : (optLeaf >= 0 && optLeaf === authLeaf ? accent : textSecond)
                                text: {
                                    if (optLeaf < 0 && authLeaf < 0) return "not registered"
                                    var s = "leaf " + (authLeaf >= 0 ? authLeaf : optLeaf)
                                    if (optLeaf >= 0 && authLeaf < 0) s += " (pending confirmation)"
                                    else if (corrected) s += " (corrected from " + optLeaf + ")"
                                    else if (optLeaf >= 0 && optLeaf === authLeaf) s += " (confirmed ✓)"
                                    return s
                                }
                            }
                        }

                        // Network status
                        RowLayout {
                            spacing: 8
                            Text {
                                font.family: root.monoFont; font.pixelSize: 10
                                color: textSecond
                                text: "NETWORK"
                            }
                            Text {
                                font.family: root.monoFont; font.pixelSize: 10
                                color: mixRdy ? accent : (peers > 0 ? root.yellow : textTertiary)
                                text: {
                                    if (peers === 0) return "no peers"
                                    var s = peers + " peers"
                                    if (mixRdy) s += " · mix pool " + pool + " ✓"
                                    else s += " · mix not ready"
                                    return s
                                }
                            }
                        }

                        // Messages
                        RowLayout {
                            spacing: 16

                            Row {
                                spacing: 4
                                Text {
                                    font.family: root.monoFont; font.pixelSize: 10
                                    color: textSecond
                                    text: "MSG OUT"
                                }
                                Rectangle {
                                    width: 28; height: 18; radius: 3
                                    color: out_ > 0 ? root.accent : root.bgPanel
                                    border.color: out_ > 0 ? root.accent : root.border
                                    Text {
                                        anchors.centerIn: parent
                                        font.family: root.monoFont; font.pixelSize: 11; font.bold: true
                                        color: out_ > 0 ? "#000" : root.textTertiary
                                        text: out_
                                    }
                                }
                            }

                            Row {
                                spacing: 4
                                Text {
                                    font.family: root.monoFont; font.pixelSize: 10
                                    color: textSecond
                                    text: "MSG IN"
                                }
                                Rectangle {
                                    width: 28; height: 18; radius: 3
                                    color: in_ > 0 ? root.accent : root.bgPanel
                                    border.color: in_ > 0 ? root.accent : root.border
                                    Text {
                                        anchors.centerIn: parent
                                        font.family: root.monoFont; font.pixelSize: 11; font.bold: true
                                        color: in_ > 0 ? "#000" : root.textTertiary
                                        text: in_
                                    }
                                }
                            }

                            // Live activity indicator
                            Rectangle {
                                id: activityDot
                                width: 8; height: 8; radius: 4
                                color: (out_ > 0 || in_ > 0) ? root.accent : root.textTertiary
                                opacity: activityAnim.running ? 1.0 : 0.3

                                SequentialAnimation on opacity {
                                    id: activityAnim
                                    running: false
                                    loops: 3
                                    NumberAnimation { to: 1.0; duration: 150 }
                                    NumberAnimation { to: 0.3; duration: 300 }
                                }

                                Connections {
                                    target: monitor
                                    function onStateChanged() {
                                        var prevOut = activityDot._lastOut || 0
                                        var prevIn = activityDot._lastIn || 0
                                        if (out_ !== prevOut || in_ !== prevIn) {
                                            activityAnim.restart()
                                        }
                                        activityDot._lastOut = out_
                                        activityDot._lastIn = in_
                                    }
                                }
                                property int _lastOut: 0
                                property int _lastIn: 0
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        // ─── CHAT HOST PANEL (only in host mode) ────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hostModeEnabled ? 200 : 0
            visible: hostModeEnabled
            color: bgSecondary
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Text {
                    font.family: root.monoFont; font.pixelSize: 13; font.bold: true
                    color: textPrimary
                    text: "CHAT HOST — " + (chatHost ? chatHost.phase : "---")
                }

                RowLayout {
                    spacing: 8

                    Button {
                        text: "Initialize"
                        enabled: chatHost && !chatHost.initialized
                        font.family: root.monoFont; font.pixelSize: 11
                        onClicked: {
                            var cfg = chatHost.readConfigFile(
                                monitor.stateDir + "/chat_sender_config.json")
                            if (!cfg) cfg = chatHost.buildConfigFromEnv()
                            chatHost.initChat(cfg)
                        }
                        background: Rectangle {
                            color: parent.enabled
                                ? (parent.pressed ? root.accentPress : parent.hovered ? root.accentHover : root.accent)
                                : root.textTertiary
                            radius: 3
                        }
                        contentItem: Text { text: parent.text; color: "#000"; font: parent.font; horizontalAlignment: Text.AlignHCenter }
                    }

                    Button {
                        text: "Start"
                        enabled: chatHost && chatHost.initialized && !chatHost.started
                        font.family: root.monoFont; font.pixelSize: 11
                        onClicked: chatHost.startChat()
                        background: Rectangle {
                            color: parent.enabled
                                ? (parent.pressed ? root.accentPress : parent.hovered ? root.accentHover : root.accent)
                                : root.textTertiary
                            radius: 3
                        }
                        contentItem: Text { text: parent.text; color: "#000"; font: parent.font; horizontalAlignment: Text.AlignHCenter }
                    }

                    Button {
                        text: "Create Bundle"
                        enabled: chatHost && chatHost.started
                        font.family: root.monoFont; font.pixelSize: 11
                        onClicked: chatHost.createIntroBundle()
                        background: Rectangle {
                            color: parent.enabled
                                ? (parent.pressed ? root.accentPress : parent.hovered ? root.accentHover : root.accent)
                                : root.textTertiary
                            radius: 3
                        }
                        contentItem: Text { text: parent.text; color: "#000"; font: parent.font; horizontalAlignment: Text.AlignHCenter }
                    }
                }

                // Intro bundle display
                TextField {
                    Layout.fillWidth: true
                    visible: chatHost && chatHost.introBundle.length > 0
                    text: chatHost ? chatHost.introBundle : ""
                    readOnly: true
                    selectByMouse: true
                    font.family: root.monoFont; font.pixelSize: 10
                    color: textPrimary
                    background: Rectangle { color: root.bgPanel; border.color: root.border; radius: 3 }
                }

                // Send conversation row
                RowLayout {
                    spacing: 4

                    TextField {
                        id: bundleInput
                        Layout.fillWidth: true
                        placeholderText: "Paste intro bundle..."
                        font.family: root.monoFont; font.pixelSize: 11
                        color: textPrimary
                        background: Rectangle { color: root.bgPanel; border.color: bundleInput.activeFocus ? root.accent : root.border; radius: 3 }
                    }

                    TextField {
                        id: msgInput
                        Layout.preferredWidth: 200
                        placeholderText: "Message..."
                        font.family: root.monoFont; font.pixelSize: 11
                        color: textPrimary
                        background: Rectangle { color: root.bgPanel; border.color: msgInput.activeFocus ? root.accent : root.border; radius: 3 }
                    }

                    Button {
                        text: "Send"
                        enabled: chatHost && chatHost.started && msgInput.text.length > 0
                        font.family: root.monoFont; font.pixelSize: 11
                        onClicked: {
                            if (bundleInput.text.length > 0 && (!chatHost.currentConvId || chatHost.currentConvId.length === 0)) {
                                chatHost.newConversation(bundleInput.text, msgInput.text)
                                bundleInput.text = ""
                            } else if (chatHost.currentConvId && chatHost.currentConvId.length > 0) {
                                chatHost.sendMessage(chatHost.currentConvId, msgInput.text)
                            }
                            msgInput.text = ""
                        }
                        background: Rectangle {
                            color: parent.enabled
                                ? (parent.pressed ? root.accentPress : parent.hovered ? root.accentHover : root.accent)
                                : root.textTertiary
                            radius: 3
                        }
                        contentItem: Text { text: parent.text; color: "#000"; font: parent.font; horizontalAlignment: Text.AlignHCenter }
                    }
                }

                Text {
                    font.family: root.monoFont; font.pixelSize: 11
                    color: textSecond
                    text: "out:" + (chatHost ? chatHost.messagesSent : 0) + " in:" + (chatHost ? chatHost.messagesReceived : 0) +
                          (chatHost && chatHost.currentConvId ? " conv:" + chatHost.currentConvId.substring(0,6) : "")
                }
            }
        }

        // ─── CHAIN EVENTS ──────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            color: bgSecondary
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                Text {
                    font.family: root.monoFont; font.pixelSize: 11; font.bold: true
                    color: textSecond
                    text: "CHAIN EVENTS"
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: chainEvents
                    clip: true

                    delegate: Text {
                        width: ListView.view.width
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: {
                            if (eventType === "TX_FAIL" || eventType === "WALLET_ERR" || eventType === "REG_FAIL")
                                return root.red
                            if (eventType === "REGISTER") return root.accent
                            if (eventType === "LEAF_FIX") return root.yellow
                            return root.textSecond
                        }
                        text: timestamp + " " + eventType + " " + detail
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
