#pragma once
#include <QObject>
#include <QTimer>
#include <QDateTime>
#include <QJsonArray>
#include "LogTailer.h"
#include "LogParser.h"
#include "ChainEventModel.h"
#include "RpcClient.h"

class MonitorBackend : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString stateDir READ stateDir CONSTANT)
    Q_PROPERTY(int blockId READ blockId NOTIFY stateChanged)
    Q_PROPERTY(int blockAgeSecs READ blockAgeSecs NOTIFY stateChanged)
    Q_PROPERTY(int txValidated READ txValidated NOTIFY stateChanged)
    Q_PROPERTY(int txFailed READ txFailed NOTIFY stateChanged)
    Q_PROPERTY(int rpcBlockId READ rpcBlockId NOTIFY stateChanged)
    Q_PROPERTY(bool rpcReachable READ rpcReachable NOTIFY stateChanged)

    Q_PROPERTY(QString mixNodeStates READ mixNodeStates NOTIFY stateChanged)

    Q_PROPERTY(bool gifterMounted READ gifterMounted NOTIFY stateChanged)
    Q_PROPERTY(int gifterQueueDepth READ gifterQueueDepth NOTIFY stateChanged)
    Q_PROPERTY(QString gifterStatus READ gifterStatus NOTIFY stateChanged)

    Q_PROPERTY(QString senderPhase READ senderPhase NOTIFY stateChanged)
    Q_PROPERTY(int senderOptLeaf READ senderOptLeaf NOTIFY stateChanged)
    Q_PROPERTY(int senderAuthLeaf READ senderAuthLeaf NOTIFY stateChanged)
    Q_PROPERTY(bool senderLeafCorrected READ senderLeafCorrected NOTIFY stateChanged)
    Q_PROPERTY(int senderPeers READ senderPeers NOTIFY stateChanged)
    Q_PROPERTY(bool senderMixReady READ senderMixReady NOTIFY stateChanged)
    Q_PROPERTY(int senderMixPool READ senderMixPool NOTIFY stateChanged)
    Q_PROPERTY(int senderMsgOut READ senderMsgOut NOTIFY stateChanged)
    Q_PROPERTY(int senderMsgIn READ senderMsgIn NOTIFY stateChanged)

    Q_PROPERTY(QString receiverPhase READ receiverPhase NOTIFY stateChanged)
    Q_PROPERTY(int receiverOptLeaf READ receiverOptLeaf NOTIFY stateChanged)
    Q_PROPERTY(int receiverAuthLeaf READ receiverAuthLeaf NOTIFY stateChanged)
    Q_PROPERTY(bool receiverLeafCorrected READ receiverLeafCorrected NOTIFY stateChanged)
    Q_PROPERTY(int receiverPeers READ receiverPeers NOTIFY stateChanged)
    Q_PROPERTY(bool receiverMixReady READ receiverMixReady NOTIFY stateChanged)
    Q_PROPERTY(int receiverMixPool READ receiverMixPool NOTIFY stateChanged)
    Q_PROPERTY(int receiverMsgOut READ receiverMsgOut NOTIFY stateChanged)
    Q_PROPERTY(int receiverMsgIn READ receiverMsgIn NOTIFY stateChanged)

public:
    explicit MonitorBackend(QObject* parent = nullptr);

    Q_INVOKABLE void setStateDir(const QString& path, bool replay = false);
    Q_INVOKABLE void setRpcUrl(const QString& url);

    QString stateDir() const { return m_stateDir; }
    int blockId() const { return m_blockId; }
    int blockAgeSecs() const;
    int txValidated() const { return m_txValidated; }
    int txFailed() const { return m_txFailed; }
    int rpcBlockId() const { return m_rpcClient ? m_rpcClient->lastBlockId() : -1; }
    bool rpcReachable() const { return m_rpcClient ? m_rpcClient->reachable() : false; }

    QString mixNodeStates() const;
    bool gifterMounted() const { return m_nodes[0].gifterMounted; }
    int gifterQueueDepth() const;
    QString gifterStatus() const;

    QString senderPhase() const { return m_sender.phase; }
    int senderOptLeaf() const { return m_sender.optLeaf; }
    int senderAuthLeaf() const { return m_sender.authLeaf; }
    bool senderLeafCorrected() const { return m_sender.leafCorrected; }
    int senderPeers() const { return m_sender.peers; }
    bool senderMixReady() const { return m_sender.mixReady; }
    int senderMixPool() const { return m_sender.mixPool; }
    int senderMsgOut() const { return m_sender.msgOut; }
    int senderMsgIn() const { return m_sender.msgIn; }

    QString receiverPhase() const { return m_receiver.phase; }
    int receiverOptLeaf() const { return m_receiver.optLeaf; }
    int receiverAuthLeaf() const { return m_receiver.authLeaf; }
    bool receiverLeafCorrected() const { return m_receiver.leafCorrected; }
    int receiverPeers() const { return m_receiver.peers; }
    bool receiverMixReady() const { return m_receiver.mixReady; }
    int receiverMixPool() const { return m_receiver.mixPool; }
    int receiverMsgOut() const { return m_receiver.msgOut; }
    int receiverMsgIn() const { return m_receiver.msgIn; }

    ChainEventModel* chainEventModel() { return &m_chainEvents; }

signals:
    void stateChanged();

private slots:
    void onSequencerLine(const QString& line);
    void onNodeLine(int idx, const QString& line);
    void onChatLine(bool isSender, const QString& line);
    void onBlockAgeTick();

private:
    void resetState();
    void addChainEvent(const QString& type, const QString& detail);
    QString nowTimestamp() const;

    struct NodeState {
        bool mixMounted = false;
        bool lezWired = false;
        bool kadReady = false;
        bool gifterMounted = false;
        bool gifterSelfReg = false;
        int gifterReqsIn = 0;
        int gifterReqsOk = 0;
        int gifterReqsFail = 0;
    };

    struct ChatState {
        QString phase = QStringLiteral("---");
        int optLeaf = -1;
        int authLeaf = -1;
        bool leafCorrected = false;
        int peers = 0;
        bool mixReady = false;
        int mixPool = 0;
        int msgOut = 0;
        int msgIn = 0;
    };

    QString m_stateDir;
    int m_blockId = 0;
    QDateTime m_lastBlockTime;
    int m_txValidated = 0;
    int m_txFailed = 0;
    NodeState m_nodes[4];
    ChatState m_sender;
    ChatState m_receiver;
    ChainEventModel m_chainEvents;
    QTimer m_blockAgeTimer;

    RpcClient* m_rpcClient = nullptr;
    LogTailer* m_seqTailer = nullptr;
    LogTailer* m_nodeTailers[4] = {};
    LogTailer* m_senderTailer = nullptr;
    LogTailer* m_receiverTailer = nullptr;
};
