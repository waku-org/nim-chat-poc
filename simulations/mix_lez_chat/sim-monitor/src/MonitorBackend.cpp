#include "MonitorBackend.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDir>

MonitorBackend::MonitorBackend(QObject* parent) : QObject(parent) {
    m_blockAgeTimer.setInterval(1000);
    connect(&m_blockAgeTimer, &QTimer::timeout, this, &MonitorBackend::onBlockAgeTick);
    m_blockAgeTimer.start();
}

void MonitorBackend::setRpcUrl(const QString& url) {
    if (m_rpcClient) { m_rpcClient->stop(); delete m_rpcClient; m_rpcClient = nullptr; }
    if (url.isEmpty()) return;
    m_rpcClient = new RpcClient(url, this);
    connect(m_rpcClient, &RpcClient::updated, this, [this]{ emit stateChanged(); });
    m_rpcClient->start();
}

void MonitorBackend::setStateDir(const QString& path, bool replay) {
    if (m_stateDir == path) return;
    m_stateDir = path;

    if (m_seqTailer) { m_seqTailer->stop(); delete m_seqTailer; m_seqTailer = nullptr; }
    for (int i = 0; i < 4; ++i) {
        if (m_nodeTailers[i]) { m_nodeTailers[i]->stop(); delete m_nodeTailers[i]; m_nodeTailers[i] = nullptr; }
    }
    if (m_senderTailer) { m_senderTailer->stop(); delete m_senderTailer; m_senderTailer = nullptr; }
    if (m_receiverTailer) { m_receiverTailer->stop(); delete m_receiverTailer; m_receiverTailer = nullptr; }
    if (m_receiver2Tailer) { m_receiver2Tailer->stop(); delete m_receiver2Tailer; m_receiver2Tailer = nullptr; }

    resetState();

    m_seqTailer = new LogTailer(QDir(path).filePath("sequencer.log"), replay, this);
    connect(m_seqTailer, &LogTailer::newLine, this, &MonitorBackend::onSequencerLine);
    connect(m_seqTailer, &LogTailer::fileReset, this, [this]{ resetState(); });
    m_seqTailer->start();

    for (int i = 0; i < 4; ++i) {
        m_nodeTailers[i] = new LogTailer(
            QDir(path).filePath(QStringLiteral("node%1.log").arg(i)), replay, this);
        connect(m_nodeTailers[i], &LogTailer::newLine, this, [this, i](const QString& l){ onNodeLine(i, l); });
        connect(m_nodeTailers[i], &LogTailer::fileReset, this, [this]{ resetState(); });
        m_nodeTailers[i]->start();
    }

    m_senderTailer = new LogTailer(QDir(path).filePath("chat_sender.log"), replay, this);
    connect(m_senderTailer, &LogTailer::newLine, this, [this](const QString& l){ onChatLine(true, l); });
    connect(m_senderTailer, &LogTailer::fileReset, this, [this]{ resetState(); });
    m_senderTailer->start();

    m_receiverTailer = new LogTailer(QDir(path).filePath("chat_receiver.log"), replay, this);
    connect(m_receiverTailer, &LogTailer::newLine, this, [this](const QString& l){ onChatLine(false, l); });
    connect(m_receiverTailer, &LogTailer::fileReset, this, [this]{ resetState(); });
    m_receiverTailer->start();

    // Receiver2 (optional — file may not exist)
    m_receiver2Tailer = new LogTailer(QDir(path).filePath("chat_receiver2.log"), replay, this);
    connect(m_receiver2Tailer, &LogTailer::newLine, this, [this](const QString& l){
        auto ev = LogParser::parseChatLine(l);
        auto& chat = m_receiver2;
        switch (ev.type) {
        case ParsedEvent::ChatInit: chat.phase = "init"; m_hasReceiver2 = true; break;
        case ParsedEvent::ChatStart: chat.phase = "start"; break;
        case ParsedEvent::ChatMembershipRequested: chat.phase = "request"; break;
        case ParsedEvent::ChatMembershipGranted:
            chat.phase = QStringLiteral("opt:%1").arg(ev.intVal); chat.optLeaf = ev.intVal; break;
        case ParsedEvent::ChatMembershipConfirmed:
            chat.phase = QStringLiteral("conf:%1").arg(ev.intVal); chat.authLeaf = ev.intVal; break;
        case ParsedEvent::ChatNewMessage: ++chat.msgIn; break;
        case ParsedEvent::ChatNewConversation: chat.phase = "intro_accepted"; break;
        case ParsedEvent::ChatPeerStatus:
            chat.peers = ev.intVal; chat.mixReady = ev.boolVal; chat.mixPool = ev.intVal2; break;
        default: return;
        }
        emit stateChanged();
    });
    connect(m_receiver2Tailer, &LogTailer::fileReset, this, [this]{ resetState(); });
    m_receiver2Tailer->start();
}

void MonitorBackend::resetState() {
    m_blockId = 0;
    m_lastBlockTime = QDateTime();
    m_txValidated = 0;
    m_txFailed = 0;
    for (auto& n : m_nodes) n = {};
    m_sender = {};
    m_receiver = {};
    m_receiver2 = {};
    m_hasReceiver2 = false;
    m_chainEvents.clear();
    emit stateChanged();
}

int MonitorBackend::blockAgeSecs() const {
    if (!m_lastBlockTime.isValid()) return -1;
    return static_cast<int>(m_lastBlockTime.secsTo(QDateTime::currentDateTime()));
}

QString MonitorBackend::mixNodeStates() const {
    QJsonArray arr;
    for (int i = 0; i < 4; ++i) {
        QJsonObject o;
        o["mounted"] = m_nodes[i].mixMounted;
        o["lez"] = m_nodes[i].lezWired;
        o["kad"] = m_nodes[i].kadReady;
        arr.append(o);
    }
    return QJsonDocument(arr).toJson(QJsonDocument::Compact);
}

int MonitorBackend::gifterQueueDepth() const {
    const auto& g = m_nodes[0];
    int depth = g.gifterReqsIn - g.gifterReqsOk - g.gifterReqsFail;
    return depth > 0 ? depth : 0;
}

QString MonitorBackend::gifterStatus() const {
    if (!m_nodes[0].gifterMounted) return QStringLiteral("not-mounted");
    int depth = gifterQueueDepth();
    if (depth > 0) return QStringLiteral("queue:%1").arg(depth);
    return QStringLiteral("idle");
}

void MonitorBackend::onSequencerLine(const QString& line) {
    static int lineCount = 0;
    if (++lineCount <= 3) qDebug() << "SEQ LINE" << lineCount << ":" << line.left(80);
    auto ev = LogParser::parseSequencerLine(line);
    if (ev.type != ParsedEvent::None && lineCount <= 10) qDebug() << "SEQ MATCH type=" << ev.type;
    switch (ev.type) {
    case ParsedEvent::SeqBlockCreated:
        m_blockId = ev.intVal;
        m_lastBlockTime = QDateTime::currentDateTime();
        break;
    case ParsedEvent::SeqTxValidated:
        ++m_txValidated;
        addChainEvent("TX_OK", QStringLiteral("hash=%1").arg(ev.strVal));
        break;
    case ParsedEvent::SeqTxFailed:
        ++m_txFailed;
        addChainEvent("TX_FAIL", QStringLiteral("hash=%1 %2").arg(ev.strVal, ev.strVal2));
        break;
    default: return;
    }
    emit stateChanged();
}

void MonitorBackend::onNodeLine(int idx, const QString& line) {
    auto ev = LogParser::parseMixNodeLine(line);
    auto& node = m_nodes[idx];
    switch (ev.type) {
    case ParsedEvent::MixMounted: node.mixMounted = true; break;
    case ParsedEvent::LezWired: node.lezWired = true; break;
    case ParsedEvent::KadReady: node.kadReady = true; break;
    case ParsedEvent::GifterMounted: node.gifterMounted = true; break;
    case ParsedEvent::GifterSelfRegistered: node.gifterSelfReg = true; break;
    case ParsedEvent::GifterAuthBounce:
        addChainEvent("GIFTER_AUTHFAIL", ev.strVal);
        break;
    case ParsedEvent::GifterReqReceived:
        ++node.gifterReqsIn;
        addChainEvent("GIFTER_REQ", QStringLiteral("req=%1").arg(ev.strVal));
        break;
    case ParsedEvent::GifterReqSucceeded:
        ++node.gifterReqsOk;
        addChainEvent("REGISTER", QStringLiteral("leaf=%1 confirmed").arg(ev.intVal));
        break;
    case ParsedEvent::GifterReqFailed:
        ++node.gifterReqsFail;
        addChainEvent("REG_FAIL", ev.strVal);
        break;
    case ParsedEvent::WalletFfiError:
        addChainEvent("WALLET_ERR", QStringLiteral("FFI error %1").arg(ev.intVal));
        break;
    default: return;
    }
    emit stateChanged();
}

void MonitorBackend::onChatLine(bool isSender, const QString& line) {
    auto ev = LogParser::parseChatLine(line);
    auto& chat = isSender ? m_sender : m_receiver;
    switch (ev.type) {
    case ParsedEvent::ChatInit: chat.phase = "init"; break;
    case ParsedEvent::ChatStart: chat.phase = "start"; break;
    case ParsedEvent::ChatMembershipRequested: chat.phase = "request"; break;
    case ParsedEvent::ChatMembershipGranted:
        chat.phase = QStringLiteral("opt:%1").arg(ev.intVal);
        chat.optLeaf = ev.intVal;
        break;
    case ParsedEvent::ChatMembershipConfirmed:
        chat.phase = QStringLiteral("conf:%1").arg(ev.intVal);
        chat.authLeaf = ev.intVal;
        if (chat.mixReady && chat.mixPool >= 4)
            chat.phase = "ready";
        break;
    case ParsedEvent::ChatLeafCorrected:
        chat.leafCorrected = true;
        chat.optLeaf = ev.intVal;
        chat.authLeaf = ev.intVal2;
        addChainEvent("LEAF_FIX",
            QStringLiteral("%1 opt=%2→auth=%3").arg(isSender ? "sender" : "receiver").arg(ev.intVal).arg(ev.intVal2));
        break;
    case ParsedEvent::ChatIntroBundleCreated:
        if (isSender) chat.phase = "intro_emitted";
        addChainEvent("BUNDLE", ev.strVal.left(30) + "...");
        break;
    case ParsedEvent::ChatNewConversation:
        if (!isSender) chat.phase = "intro_accepted";
        break;
    case ParsedEvent::ChatNewMessage:
        ++chat.msgIn;
        if (!isSender && chat.msgIn == 1) chat.phase = "msg_received";
        break;
    case ParsedEvent::ChatSendResult:
        if (ev.boolVal) {
            ++chat.msgOut;
            if (isSender && chat.msgOut == 1) chat.phase = "msg_sent";
        }
        break;
    case ParsedEvent::ChatPeerStatus:
        chat.peers = ev.intVal;
        chat.mixReady = ev.boolVal;
        chat.mixPool = ev.intVal2;
        if (chat.phase.startsWith("conf:") && chat.mixReady && chat.mixPool >= 4)
            chat.phase = "ready";
        break;
    case ParsedEvent::RlnRootsPolled:
        addChainEvent("ROOTS", QStringLiteral("count=%1").arg(ev.intVal));
        break;
    default: return;
    }
    emit stateChanged();
}

void MonitorBackend::onBlockAgeTick() {
    if (m_lastBlockTime.isValid()) emit stateChanged();
}

void MonitorBackend::addChainEvent(const QString& type, const QString& detail) {
    m_chainEvents.prepend(nowTimestamp(), type, detail);
}

QString MonitorBackend::nowTimestamp() const {
    return QDateTime::currentDateTime().toString("HH:mm:ss");
}
