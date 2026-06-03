#pragma once
#include <QObject>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class RpcClient : public QObject {
    Q_OBJECT
public:
    explicit RpcClient(const QString& url, QObject* parent = nullptr);
    void start();
    void stop();

    int lastBlockId() const { return m_lastBlockId; }
    bool reachable() const { return m_reachable; }

signals:
    void updated();

private slots:
    void poll();
    void onReply(QNetworkReply* reply);

private:
    QString m_url;
    QNetworkAccessManager m_nam;
    QTimer m_timer;
    int m_lastBlockId = -1;
    bool m_reachable = false;
    int m_requestId = 0;
};
