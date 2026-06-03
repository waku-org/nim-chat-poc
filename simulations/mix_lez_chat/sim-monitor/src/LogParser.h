#pragma once
#include <QString>
#include <QRegularExpression>
#include <QVariant>

struct ParsedEvent {
    enum Type {
        None = 0,
        SeqBlockCreated,
        SeqTxValidated,
        SeqTxFailed,
        MixMounted,
        LezWired,
        GifterMounted,
        GifterSelfRegistered,
        GifterReqReceived,
        GifterReqSucceeded,
        GifterReqFailed,
        WalletFfiError,
        KadReady,
        GifterAuthBounce,
        ChatInit,
        ChatStart,
        ChatIntroBundleCreated,
        ChatMembershipRequested,
        ChatMembershipGranted,
        ChatMembershipConfirmed,
        ChatLeafCorrected,
        ChatNewConversation,
        ChatNewMessage,
        ChatSendResult,
        ChatPeerStatus,
        RlnRootsPolled,
        RlnFetchFailed,
    };

    Type type = None;
    int intVal = 0;
    int intVal2 = 0;
    bool boolVal = false;
    QString strVal;
    QString strVal2;
};

class LogParser {
public:
    static QString stripAnsi(const QString& line);
    static QString stripLogosHostPrefix(const QString& line);

    static ParsedEvent parseSequencerLine(const QString& line);
    static ParsedEvent parseMixNodeLine(const QString& line);
    static ParsedEvent parseChatLine(const QString& line);
};
