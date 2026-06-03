#include "ChatHost.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QCoreApplication>
#include <QDir>
#include <QDebug>

#ifdef ENABLE_HOST_MODE
#include <logos_core.h>
#include <logos_api.h>
#include <logos_api_client.h>
#endif

ChatHost::ChatHost(QObject* parent) : QObject(parent) {}

ChatHost::~ChatHost() {
#ifdef ENABLE_HOST_MODE
    if (m_modulesLoaded) {
        logos_core_cleanup();
    }
    delete static_cast<LogosAPI*>(m_logosAPI);
#endif
}

bool ChatHost::loadModules(const QString& modulesDir, const QString& dataDir) {
#ifdef ENABLE_HOST_MODE
    logos_core_add_modules_dir(modulesDir.toUtf8().constData());
    logos_core_set_persistence_base_path(dataDir.toUtf8().constData());
    logos_core_start();

    const char* modules[] = {
        "capability_module",
        "logos_execution_zone",
        "liblogos_rln_module",
        "chat_module",
    };

    for (const char* mod : modules) {
        emit logLine(QStringLiteral("Loading module: %1").arg(QString::fromUtf8(mod)));
        int rc = logos_core_load_module_with_dependencies(mod);
        if (rc != 1) {
            emit logLine(QStringLiteral("ERROR: Failed to load module: %1 (rc=%2)")
                .arg(QString::fromUtf8(mod)).arg(rc));
            return false;
        }
        emit logLine(QStringLiteral("Loaded: %1").arg(QString::fromUtf8(mod)));
    }

    m_modulesLoaded = true;

    auto* api = new LogosAPI("sim_monitor", this);
    m_logosAPI = api;
    m_chatClient = api->getClient("chat_module");

    if (!m_chatClient) {
        emit logLine("ERROR: Could not get chat_module client");
        return false;
    }

    setupEventHandlers();
    emit logLine("Chat host ready — modules loaded, event handlers wired");
    return true;
#else
    Q_UNUSED(modulesDir); Q_UNUSED(dataDir);
    emit logLine("ERROR: Host mode not compiled (ENABLE_HOST_MODE=OFF)");
    return false;
#endif
}

void ChatHost::setupEventHandlers() {
#ifdef ENABLE_HOST_MODE
    if (!m_chatClient) return;
    auto* client = static_cast<LogosAPIClient*>(m_chatClient);

    auto* chatObj = client->requestObject("chat_module");
    if (!chatObj) {
        emit logLine("WARNING: Could not request chat_module object for events");
        return;
    }

    client->onEvent(chatObj, "chatInitResult",
        [this](const QString&, const QVariantList& args) { onChatInitResult(args); });
    client->onEvent(chatObj, "chatStartResult",
        [this](const QString&, const QVariantList& args) { onChatStartResult(args); });
    client->onEvent(chatObj, "chatCreateIntroBundleResult",
        [this](const QString&, const QVariantList& args) { onIntroBundleResult(args); });
    client->onEvent(chatObj, "chatNewConversation",
        [this](const QString&, const QVariantList& args) { onNewConversation(args); });
    client->onEvent(chatObj, "chatNewMessage",
        [this](const QString&, const QVariantList& args) { onNewMessage(args); });
    client->onEvent(chatObj, "chatSendMessageResult",
        [this](const QString&, const QVariantList& args) { onSendResult(args); });
    client->onEvent(chatObj, "chatNewPrivateConversationResult",
        [this](const QString&, const QVariantList& args) { onNewPrivateConvResult(args); });

    emit logLine("Event handlers wired for chat_module");
#endif
}

void ChatHost::initChat(const QString& configJson) {
#ifdef ENABLE_HOST_MODE
    if (!m_chatClient) return;
    auto* client = static_cast<LogosAPIClient*>(m_chatClient);
    emit logLine("initChat: calling...");
    QVariant result = client->invokeRemoteMethod("chat_module", "initChat", configJson);
    emit logLine(QStringLiteral("initChat: result=%1").arg(result.toString()));
#else
    Q_UNUSED(configJson);
#endif
}

void ChatHost::startChat() {
#ifdef ENABLE_HOST_MODE
    if (!m_chatClient) return;
    auto* client = static_cast<LogosAPIClient*>(m_chatClient);
    emit logLine("startChat: calling...");
    client->invokeRemoteMethod("chat_module", "startChat");
    client->invokeRemoteMethod("chat_module", "setEventCallback");
    emit logLine("startChat + setEventCallback: done");
#endif
}

void ChatHost::createIntroBundle() {
#ifdef ENABLE_HOST_MODE
    if (!m_chatClient) return;
    auto* client = static_cast<LogosAPIClient*>(m_chatClient);
    emit logLine("createIntroBundle: calling...");
    client->invokeRemoteMethod("chat_module", "createIntroBundle");
#endif
}

void ChatHost::newConversation(const QString& introBundle, const QString& firstMessage) {
#ifdef ENABLE_HOST_MODE
    if (!m_chatClient) return;
    auto* client = static_cast<LogosAPIClient*>(m_chatClient);
    QString msgHex = toHex(firstMessage);
    emit logLine("newPrivateConversation: calling...");
    client->invokeRemoteMethod("chat_module", "newPrivateConversation",
        QVariant(introBundle), QVariant(msgHex));
#else
    Q_UNUSED(introBundle); Q_UNUSED(firstMessage);
#endif
}

void ChatHost::sendMessage(const QString& convId, const QString& message) {
#ifdef ENABLE_HOST_MODE
    if (!m_chatClient) return;
    auto* client = static_cast<LogosAPIClient*>(m_chatClient);
    QString msgHex = toHex(message);
    client->invokeRemoteMethod("chat_module", "sendMessage",
        QVariant(convId), QVariant(msgHex));
#else
    Q_UNUSED(convId); Q_UNUSED(message);
#endif
}

// ─── Event handlers ───

void ChatHost::onChatInitResult(const QVariantList& args) {
    if (args.size() > 0 && args[0].toBool()) {
        m_initialized = true;
        m_phase = "init";
        emit logLine("EVENT: chatInitResult → initialized");
        emit stateChanged();
    }
    emit chatEvent("chatInitResult", args);
}

void ChatHost::onChatStartResult(const QVariantList& args) {
    if (args.size() > 0 && args[0].toBool()) {
        m_started = true;
        m_phase = "start";
        emit logLine("EVENT: chatStartResult → started");
        emit stateChanged();
    }
    emit chatEvent("chatStartResult", args);
}

void ChatHost::onIntroBundleResult(const QVariantList& args) {
    if (args.size() > 1) {
        m_introBundle = args[1].toString();
        m_phase = "intro_emitted";
        emit logLine("EVENT: introBundleResult → " + m_introBundle.left(30) + "...");
        emit stateChanged();
    }
    emit chatEvent("chatCreateIntroBundleResult", args);
}

void ChatHost::onNewConversation(const QVariantList& args) {
    if (args.size() > 0) {
        m_currentConvId = args[0].toString();
        emit logLine("EVENT: newConversation → " + m_currentConvId.left(10));
        emit stateChanged();
    }
    emit chatEvent("chatNewConversation", args);
}

void ChatHost::onNewMessage(const QVariantList& args) {
    ++m_messagesReceived;
    if (m_messagesReceived == 1) m_phase = "msg_received";

    QString body;
    if (args.size() > 2) body = fromHex(args[2].toString());
    emit logLine(QStringLiteral("EVENT: chatNewMessage #%1: %2")
        .arg(m_messagesReceived).arg(body.left(40)));
    emit stateChanged();
    emit chatEvent("chatNewMessage", args);
}

void ChatHost::onSendResult(const QVariantList& args) {
    if (args.size() > 0 && args[0].toBool()) {
        ++m_messagesSent;
        if (m_messagesSent == 1) m_phase = "msg_sent";
        emit stateChanged();
    }
    emit chatEvent("chatSendMessageResult", args);
}

void ChatHost::onNewPrivateConvResult(const QVariantList& args) {
    if (args.size() > 1) {
        m_currentConvId = args[1].toString();
        emit logLine("EVENT: newPrivateConvResult → " + m_currentConvId.left(10));
        emit stateChanged();
    }
    emit chatEvent("chatNewPrivateConversationResult", args);
}

// ─── Config builders ───

QString ChatHost::buildConfigFromEnv() {
    QJsonObject config;

    auto env = [](const char* name, const QString& def = {}) -> QString {
        QString val = qEnvironmentVariable(name);
        return val.isEmpty() ? def : val;
    };

    config["name"] = env("CHAT_NAME", QStringLiteral("monitor_user"));
    config["clusterId"] = env("CHAT_CLUSTER_ID", "99").toInt();
    config["shardId"] = env("CHAT_SHARD_ID", "0").toInt();
    config["port"] = env("CHAT_PORT", "0").toInt();

    QString mixNodes = env("CHAT_MIX_NODES");
    if (!mixNodes.isEmpty()) {
        QJsonArray arr;
        for (const auto& n : mixNodes.split(',', Qt::SkipEmptyParts))
            arr.append(n.trimmed());
        config["mixNodes"] = arr;
        config["mixEnabled"] = true;
        config["minMixPoolSize"] = env("CHAT_MIN_MIX_POOL_SIZE", "4").toInt();
    }

    QString staticPeers = env("CHAT_STATIC_PEERS");
    if (!staticPeers.isEmpty()) {
        QJsonArray arr;
        for (const auto& p : staticPeers.split(',', Qt::SkipEmptyParts))
            arr.append(p.trimmed());
        config["staticPeers"] = arr;
    }

    QString destPeer = env("CHAT_DEST_PEER_ADDR");
    if (!destPeer.isEmpty()) config["destPeerAddr"] = destPeer;

    QString gifterNode = env("CHAT_GIFTER_NODE_ADDR");
    if (!gifterNode.isEmpty()) config["gifterNodeAddr"] = gifterNode;

    QString gifterKey = env("CHAT_GIFTER_AUTH_KEY");
    if (!gifterKey.isEmpty()) config["gifterAuthKey"] = gifterKey;

    return QJsonDocument(config).toJson(QJsonDocument::Compact);
}

QString ChatHost::readConfigFile(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QString::fromUtf8(f.readAll());
}

// ─── Helpers ───

QString ChatHost::toHex(const QString& text) {
    return QString::fromLatin1(text.toUtf8().toHex());
}

QString ChatHost::fromHex(const QString& hex) {
    return QString::fromUtf8(QByteArray::fromHex(hex.toLatin1()));
}
