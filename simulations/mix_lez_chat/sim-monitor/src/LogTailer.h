#pragma once
#include <QObject>
#include <QFile>
#include <QTimer>
#include <QString>

class LogTailer : public QObject {
    Q_OBJECT
public:
    explicit LogTailer(const QString& filePath, bool replay = false, QObject* parent = nullptr);
    void start();
    void stop();
    void reset();

signals:
    void newLine(const QString& line);
    void fileReset();

private slots:
    void poll();

private:
    void tryOpen();
    void readNewLines();

    QString m_filePath;
    bool m_replay;
    QFile m_file;
    QTimer m_timer;
    qint64 m_lastInode = -1;
    bool m_open = false;
    bool m_wasReset = false;
    bool m_debugOnce = true;
};
