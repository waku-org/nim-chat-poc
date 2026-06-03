#include "LogTailer.h"
#include <QFileInfo>
#include <QTextStream>
#include <QDebug>

LogTailer::LogTailer(const QString& filePath, bool replay, QObject* parent)
    : QObject(parent), m_filePath(filePath), m_replay(replay) {
    m_timer.setInterval(100);
    connect(&m_timer, &QTimer::timeout, this, &LogTailer::poll);
}

void LogTailer::start() {
    tryOpen();
    m_timer.start();
}

void LogTailer::stop() {
    m_timer.stop();
    if (m_open) { m_file.close(); m_open = false; }
}

void LogTailer::reset() {
    if (m_open) { m_file.close(); m_open = false; }
    m_lastInode = -1;
    m_wasReset = true;
    emit fileReset();
}

void LogTailer::tryOpen() {
    if (m_open) return;
    QFileInfo fi(m_filePath);
    if (!fi.exists()) { qDebug() << "TAILER: file not found:" << m_filePath; return; }

    m_file.setFileName(m_filePath);
    if (!m_file.open(QIODevice::ReadOnly | QIODevice::Text)) { qDebug() << "TAILER: open failed:" << m_filePath; return; }

    m_lastInode = fi.fileTime(QFileDevice::FileModificationTime).toMSecsSinceEpoch();
    m_open = true;

    if (!m_replay && !m_wasReset) m_file.seek(m_file.size());
    qDebug() << "TAILER: opened" << m_filePath << "replay=" << m_replay << "pos=" << m_file.pos() << "size=" << m_file.size();
}

void LogTailer::poll() {
    if (!m_open) {
        tryOpen();
        return;
    }

    QFileInfo fi(m_filePath);
    if (!fi.exists()) {
        reset();
        return;
    }

    if (fi.size() < m_file.pos()) {
        qDebug() << "TAILER: file shrunk, resetting" << m_filePath;
        reset();
        tryOpen();
        return;
    }

    readNewLines();
}

void LogTailer::readNewLines() {
    int count = 0;
    while (!m_file.atEnd()) {
        QByteArray bytes = m_file.readLine();
        QString line = QString::fromUtf8(bytes).trimmed();
        if (!line.isEmpty()) {
            emit newLine(line);
            ++count;
        }
    }
    if (m_debugOnce && count > 0) {
        m_debugOnce = false;
        qDebug() << "TAILER: first read from" << m_filePath << "lines=" << count;
    }
}
