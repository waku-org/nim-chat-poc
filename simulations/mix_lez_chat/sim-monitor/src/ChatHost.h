#pragma once
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

class ChatHost : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString phase READ phase NOTIFY stateChanged)
    Q_PROPERTY(bool initialized READ initialized NOTIFY stateChanged)
    Q_PROPERTY(bool started READ started NOTIFY stateChanged)
    Q_PROPERTY(QString introBundle READ introBundle NOTIFY stateChanged)
    Q_PROPERTY(QString currentConvId READ currentConvId NOTIFY stateChanged)
    Q_PROPERTY(int messagesReceived READ messagesReceived NOTIFY stateChanged)
    Q_PROPERTY(int messagesSent READ messagesSent NOTIFY stateChanged)

public:
    explicit ChatHost(QObject* parent = nullptr);
    ~ChatHost();

    bool loadModules(const QString& modulesDir, const QString& dataDir);

    Q_INVOKABLE void initChat(const QString& configJson);
    Q_INVOKABLE void startChat();
    Q_INVOKABLE void createIntroBundle();
    Q_INVOKABLE void newConversation(const QString& introBundle, const QString& firstMessage);
    Q_INVOKABLE void sendMessage(const QString& convId, const QString& message);

    Q_INVOKABLE static QString buildConfigFromEnv();
    Q_INVOKABLE static QString readConfigFile(const QString& path);

    QString phase() const { return m_phase; }
    bool initialized() const { return m_initialized; }
    bool started() const { return m_started; }
    QString introBundle() const { return m_introBundle; }
    QString currentConvId() const { return m_currentConvId; }
    int messagesReceived() const { return m_messagesReceived; }
    int messagesSent() const { return m_messagesSent; }

signals:
    void stateChanged();
    void chatEvent(const QString& eventName, const QVariantList& args);
    void logLine(const QString& line);

private:
    void setupEventHandlers();
    void onChatInitResult(const QVariantList& args);
    void onChatStartResult(const QVariantList& args);
    void onIntroBundleResult(const QVariantList& args);
    void onNewConversation(const QVariantList& args);
    void onNewMessage(const QVariantList& args);
    void onSendResult(const QVariantList& args);
    void onNewPrivateConvResult(const QVariantList& args);

    static QString toHex(const QString& text);
    static QString fromHex(const QString& hex);

    QString m_phase = "---";
    bool m_initialized = false;
    bool m_started = false;
    QString m_introBundle;
    QString m_currentConvId;
    int m_messagesReceived = 0;
    int m_messagesSent = 0;
    bool m_modulesLoaded = false;

    void* m_logosAPI = nullptr;     // LogosAPI* (only when ENABLE_HOST_MODE)
    void* m_chatClient = nullptr;   // LogosAPIClient* (only when ENABLE_HOST_MODE)
};
