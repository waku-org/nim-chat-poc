#include "RpcClient.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QUrl>

RpcClient::RpcClient(const QString& url, QObject* parent)
    : QObject(parent), m_url(url) {
    m_timer.setInterval(5000);
    connect(&m_timer, &QTimer::timeout, this, &RpcClient::poll);
    connect(&m_nam, &QNetworkAccessManager::finished, this, &RpcClient::onReply);
}

void RpcClient::start() {
    poll();
    m_timer.start();
}

void RpcClient::stop() {
    m_timer.stop();
}

void RpcClient::poll() {
    QJsonObject req;
    req["jsonrpc"] = "2.0";
    req["method"] = "getLastBlockId";
    req["params"] = QJsonArray();
    req["id"] = ++m_requestId;

    QNetworkRequest request{QUrl(m_url)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setTransferTimeout(4000);

    m_nam.post(request, QJsonDocument(req).toJson(QJsonDocument::Compact));
}

void RpcClient::onReply(QNetworkReply* reply) {
    reply->deleteLater();
    if (reply->error() != QNetworkReply::NoError) {
        if (m_reachable) { m_reachable = false; emit updated(); }
        return;
    }

    QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
    if (!doc.isObject()) {
        if (m_reachable) { m_reachable = false; emit updated(); }
        return;
    }

    QJsonValue result = doc.object().value("result");
    if (result.isDouble()) {
        m_lastBlockId = static_cast<int>(result.toDouble());
        m_reachable = true;
        emit updated();
    }
}
