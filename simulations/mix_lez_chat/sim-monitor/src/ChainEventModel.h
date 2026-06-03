#pragma once
#include <QAbstractListModel>
#include <QVector>
#include <QString>

class ChainEventModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles { TimestampRole = Qt::UserRole + 1, EventTypeRole, DetailRole };

    explicit ChainEventModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& = {}) const override { return m_items.size(); }

    QVariant data(const QModelIndex& index, int role) const override {
        if (!index.isValid() || index.row() >= m_items.size()) return {};
        const auto& item = m_items[index.row()];
        switch (role) {
        case TimestampRole: return item.timestamp;
        case EventTypeRole: return item.eventType;
        case DetailRole:    return item.detail;
        default: return {};
        }
    }

    QHash<int, QByteArray> roleNames() const override {
        return {{TimestampRole, "timestamp"}, {EventTypeRole, "eventType"}, {DetailRole, "detail"}};
    }

    void prepend(const QString& timestamp, const QString& eventType, const QString& detail) {
        if (m_items.size() >= 200) {
            beginRemoveRows({}, m_items.size() - 1, m_items.size() - 1);
            m_items.removeLast();
            endRemoveRows();
        }
        beginInsertRows({}, 0, 0);
        m_items.prepend({timestamp, eventType, detail});
        endInsertRows();
    }

    void clear() {
        beginResetModel();
        m_items.clear();
        endResetModel();
    }

private:
    struct Item { QString timestamp; QString eventType; QString detail; };
    QVector<Item> m_items;
};
