#include "LogParser.h"

static const QRegularExpression s_ansiRe(QStringLiteral("\\x1b\\[[0-9;]*m"));
// Old sim format: Debug: [LOGOS_HOST "module" ]: "..."
static const QRegularExpression s_hostPrefixRe(
    QStringLiteral("Debug: \\[LOGOS_HOST \"[^\"]+\" \\]: \"(.*)\"$"));
// LGX sim format: [timestamp] [out] [module] ...content...
static const QRegularExpression s_lgxPrefixRe(
    QStringLiteral("^\\[\\d{4}-\\d{2}-\\d{2} [^\\]]+\\] \\[(?:out|err|info|debug|warn)\\] \\[[^\\]]+\\] (.*)$"));

QString LogParser::stripAnsi(const QString& line) {
    QString out = line;
    out.remove(s_ansiRe);
    return out;
}

QString LogParser::stripLogosHostPrefix(const QString& line) {
    auto m = s_hostPrefixRe.match(line);
    if (m.hasMatch()) return stripAnsi(m.captured(1));
    QString clean = stripAnsi(line);
    m = s_lgxPrefixRe.match(clean);
    if (m.hasMatch()) return m.captured(1);
    return clean;
}

ParsedEvent LogParser::parseSequencerLine(const QString& raw) {
    QString line = stripAnsi(raw);
    ParsedEvent ev;

    static const QRegularExpression reBlock(QStringLiteral("Block with id (\\d+) created"));
    static const QRegularExpression reTxOk(QStringLiteral("Validated transaction with hash ([0-9a-f]+)"));
    static const QRegularExpression reTxFail(
        QStringLiteral("Transaction with hash ([0-9a-f]+) failed execution check with error: (.+), skipping"));

    auto m = reBlock.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::SeqBlockCreated;
        ev.intVal = m.captured(1).toInt();
        return ev;
    }
    m = reTxOk.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::SeqTxValidated;
        ev.strVal = m.captured(1).left(8);
        return ev;
    }
    m = reTxFail.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::SeqTxFailed;
        ev.strVal = m.captured(1).left(8);
        ev.strVal2 = m.captured(2);
        return ev;
    }
    return ev;
}

ParsedEvent LogParser::parseMixNodeLine(const QString& raw) {
    QString line = stripLogosHostPrefix(raw);
    ParsedEvent ev;

    if (line.contains(QStringLiteral("mounting mix protocol"))) {
        ev.type = ParsedEvent::MixMounted;
        return ev;
    }
    if (line.contains(QStringLiteral("Wired LEZ callbacks"))) {
        ev.type = ParsedEvent::LezWired;
        return ev;
    }
    if (line.contains(QStringLiteral("RLN gifter service mounted"))) {
        ev.type = ParsedEvent::GifterMounted;
        return ev;
    }
    if (line.contains(QStringLiteral("Gifter self-registered as mix relay"))) {
        ev.type = ParsedEvent::GifterSelfRegistered;
        return ev;
    }
    if (line.contains(QStringLiteral("Successfully started discovery v5")) ||
        line.contains(QStringLiteral("kademlia discovery started"))) {
        ev.type = ParsedEvent::KadReady;
        return ev;
    }
    if (line.contains(QStringLiteral("address not allowlisted")) ||
        line.contains(QStringLiteral("signature verification failed"))) {
        ev.type = ParsedEvent::GifterAuthBounce;
        int idx = line.indexOf(QStringLiteral(": "));
        ev.strVal = idx >= 0 ? line.mid(idx + 2).left(60) : line.right(60);
        return ev;
    }

    static const QRegularExpression reGifterReq(
        QStringLiteral("handling RLN gifter request.*requestId=(\\S+)"));
    auto m = reGifterReq.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::GifterReqReceived;
        ev.strVal = m.captured(1).left(10);
        return ev;
    }

    static const QRegularExpression reGifterOk(
        QStringLiteral("RLN gifter registration succeeded.*leafIndex=(\\d+)"));
    m = reGifterOk.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::GifterReqSucceeded;
        ev.intVal = m.captured(1).toInt();
        return ev;
    }

    static const QRegularExpression reGifterFail(
        QStringLiteral("RLN gifter registration failed.*error=\"(.+)\""));
    m = reGifterFail.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::GifterReqFailed;
        ev.strVal = m.captured(1);
        return ev;
    }

    static const QRegularExpression reWalletErr(
        QStringLiteral("send_public_transaction: wallet FFI error (\\d+)"));
    m = reWalletErr.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::WalletFfiError;
        ev.intVal = m.captured(1).toInt();
        return ev;
    }

    return ev;
}

ParsedEvent LogParser::parseChatLine(const QString& raw) {
    QString line = stripLogosHostPrefix(raw);
    ParsedEvent ev;

    // Both formats: EVENT:chatInitResult:true (old stderr) and emitEvent: "chatInitResult" (lgx)
    if (line.contains(QStringLiteral("EVENT:chatInitResult:true")) ||
        line.contains(QStringLiteral("emitEvent: \"chatInitResult\""))) {
        ev.type = ParsedEvent::ChatInit;
        return ev;
    }
    if (line.contains(QStringLiteral("EVENT:chatStartResult:true")) ||
        line.contains(QStringLiteral("emitEvent: \"chatStartResult\""))) {
        ev.type = ParsedEvent::ChatStart;
        return ev;
    }

    static const QRegularExpression reBundle(
        QStringLiteral("EVENT:chatCreateIntroBundleResult:(logos_chatintro_\\S+)"));
    auto m = reBundle.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::ChatIntroBundleCreated;
        ev.strVal = m.captured(1);
        return ev;
    }
    if (line.contains(QStringLiteral("emitEvent: \"chatCreateIntroBundleResult\""))) {
        ev.type = ParsedEvent::ChatIntroBundleCreated;
        return ev;
    }

    if (line.contains(QStringLiteral("requesting RLN membership from gifter"))) {
        ev.type = ParsedEvent::ChatMembershipRequested;
        return ev;
    }

    static const QRegularExpression reGranted(
        QStringLiteral("RLN membership granted.*leafIndex=(\\d+)"));
    m = reGranted.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::ChatMembershipGranted;
        ev.intVal = m.captured(1).toInt();
        return ev;
    }

    static const QRegularExpression reConfirmed(
        QStringLiteral("membership confirmed on-chain.*leafIndex=(\\d+)"));
    m = reConfirmed.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::ChatMembershipConfirmed;
        ev.intVal = m.captured(1).toInt();
        return ev;
    }

    static const QRegularExpression reCorrected(
        QStringLiteral("membership leaf corrected.*optimistic=(\\d+).*authoritative=(\\d+)"));
    m = reCorrected.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::ChatLeafCorrected;
        ev.intVal = m.captured(1).toInt();
        ev.intVal2 = m.captured(2).toInt();
        return ev;
    }

    if (line.contains(QStringLiteral("EVENT:chatNewConversation:")) ||
        line.contains(QStringLiteral("emitEvent: \"chatNewConversation\""))) {
        ev.type = ParsedEvent::ChatNewConversation;
        int idx = line.indexOf(QStringLiteral("EVENT:chatNewConversation:"));
        if (idx >= 0) ev.strVal = line.mid(idx + 25);
        return ev;
    }

    if (line.contains(QStringLiteral("EVENT:chatNewMessage:")) ||
        line.contains(QStringLiteral("emitEvent: \"chatNewMessage\""))) {
        ev.type = ParsedEvent::ChatNewMessage;
        return ev;
    }

    if (line.contains(QStringLiteral("EVENT:chatNewPrivateConversationResult:true")) ||
        line.contains(QStringLiteral("EVENT:chatSendMessageResult:true")) ||
        line.contains(QStringLiteral("emitEvent: \"chatNewPrivateConversationResult\"")) ||
        line.contains(QStringLiteral("emitEvent: \"chatSendMessageResult\""))) {
        ev.type = ParsedEvent::ChatSendResult;
        ev.boolVal = true;
        return ev;
    }

    static const QRegularExpression rePeerStatus(
        QStringLiteral("Peer status.*connectedPeers=(\\d+).*mixReady=(true|false).*mixPoolSize=(\\d+)"));
    m = rePeerStatus.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::ChatPeerStatus;
        ev.intVal = m.captured(1).toInt();
        ev.boolVal = (m.captured(2) == QStringLiteral("true"));
        ev.intVal2 = m.captured(3).toInt();
        return ev;
    }

    static const QRegularExpression reRoots(
        QStringLiteral("get_valid_roots:.*count=\\s*(\\d+)"));
    m = reRoots.match(line);
    if (m.hasMatch()) {
        ev.type = ParsedEvent::RlnRootsPolled;
        ev.intVal = m.captured(1).toInt();
        return ev;
    }

    if (line.contains(QStringLiteral("fetchAccountData failed: empty data"))) {
        ev.type = ParsedEvent::RlnFetchFailed;
        return ev;
    }

    return ev;
}
