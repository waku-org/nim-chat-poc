/****************************************************************************
** Meta object code from reading C++ file 'MonitorBackend.h'
**
** Created by: The Qt Meta Object Compiler version 69 (Qt 6.11.0)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "../../../src/MonitorBackend.h"
#include <QtNetwork/QSslError>
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'MonitorBackend.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 69
#error "This file was generated using the moc from 6.11.0. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN14MonitorBackendE_t {};
} // unnamed namespace

template <> constexpr inline auto MonitorBackend::qt_create_metaobjectdata<qt_meta_tag_ZN14MonitorBackendE_t>()
{
    namespace QMC = QtMocConstants;
    QtMocHelpers::StringRefStorage qt_stringData {
        "MonitorBackend",
        "stateChanged",
        "",
        "onSequencerLine",
        "line",
        "onNodeLine",
        "idx",
        "onChatLine",
        "isSender",
        "onBlockAgeTick",
        "setStateDir",
        "path",
        "replay",
        "setRpcUrl",
        "url",
        "stateDir",
        "blockId",
        "blockAgeSecs",
        "txValidated",
        "txFailed",
        "rpcBlockId",
        "rpcReachable",
        "mixNodeStates",
        "gifterMounted",
        "gifterQueueDepth",
        "gifterStatus",
        "senderPhase",
        "senderOptLeaf",
        "senderAuthLeaf",
        "senderLeafCorrected",
        "senderPeers",
        "senderMixReady",
        "senderMixPool",
        "senderMsgOut",
        "senderMsgIn",
        "receiverPhase",
        "receiverOptLeaf",
        "receiverAuthLeaf",
        "receiverLeafCorrected",
        "receiverPeers",
        "receiverMixReady",
        "receiverMixPool",
        "receiverMsgOut",
        "receiverMsgIn"
    };

    QtMocHelpers::UintData qt_methods {
        // Signal 'stateChanged'
        QtMocHelpers::SignalData<void()>(1, 2, QMC::AccessPublic, QMetaType::Void),
        // Slot 'onSequencerLine'
        QtMocHelpers::SlotData<void(const QString &)>(3, 2, QMC::AccessPrivate, QMetaType::Void, {{
            { QMetaType::QString, 4 },
        }}),
        // Slot 'onNodeLine'
        QtMocHelpers::SlotData<void(int, const QString &)>(5, 2, QMC::AccessPrivate, QMetaType::Void, {{
            { QMetaType::Int, 6 }, { QMetaType::QString, 4 },
        }}),
        // Slot 'onChatLine'
        QtMocHelpers::SlotData<void(bool, const QString &)>(7, 2, QMC::AccessPrivate, QMetaType::Void, {{
            { QMetaType::Bool, 8 }, { QMetaType::QString, 4 },
        }}),
        // Slot 'onBlockAgeTick'
        QtMocHelpers::SlotData<void()>(9, 2, QMC::AccessPrivate, QMetaType::Void),
        // Method 'setStateDir'
        QtMocHelpers::MethodData<void(const QString &, bool)>(10, 2, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::QString, 11 }, { QMetaType::Bool, 12 },
        }}),
        // Method 'setStateDir'
        QtMocHelpers::MethodData<void(const QString &)>(10, 2, QMC::AccessPublic | QMC::MethodCloned, QMetaType::Void, {{
            { QMetaType::QString, 11 },
        }}),
        // Method 'setRpcUrl'
        QtMocHelpers::MethodData<void(const QString &)>(13, 2, QMC::AccessPublic, QMetaType::Void, {{
            { QMetaType::QString, 14 },
        }}),
    };
    QtMocHelpers::UintData qt_properties {
        // property 'stateDir'
        QtMocHelpers::PropertyData<QString>(15, QMetaType::QString, QMC::DefaultPropertyFlags | QMC::Constant),
        // property 'blockId'
        QtMocHelpers::PropertyData<int>(16, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'blockAgeSecs'
        QtMocHelpers::PropertyData<int>(17, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'txValidated'
        QtMocHelpers::PropertyData<int>(18, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'txFailed'
        QtMocHelpers::PropertyData<int>(19, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'rpcBlockId'
        QtMocHelpers::PropertyData<int>(20, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'rpcReachable'
        QtMocHelpers::PropertyData<bool>(21, QMetaType::Bool, QMC::DefaultPropertyFlags, 0),
        // property 'mixNodeStates'
        QtMocHelpers::PropertyData<QString>(22, QMetaType::QString, QMC::DefaultPropertyFlags, 0),
        // property 'gifterMounted'
        QtMocHelpers::PropertyData<bool>(23, QMetaType::Bool, QMC::DefaultPropertyFlags, 0),
        // property 'gifterQueueDepth'
        QtMocHelpers::PropertyData<int>(24, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'gifterStatus'
        QtMocHelpers::PropertyData<QString>(25, QMetaType::QString, QMC::DefaultPropertyFlags, 0),
        // property 'senderPhase'
        QtMocHelpers::PropertyData<QString>(26, QMetaType::QString, QMC::DefaultPropertyFlags, 0),
        // property 'senderOptLeaf'
        QtMocHelpers::PropertyData<int>(27, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'senderAuthLeaf'
        QtMocHelpers::PropertyData<int>(28, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'senderLeafCorrected'
        QtMocHelpers::PropertyData<bool>(29, QMetaType::Bool, QMC::DefaultPropertyFlags, 0),
        // property 'senderPeers'
        QtMocHelpers::PropertyData<int>(30, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'senderMixReady'
        QtMocHelpers::PropertyData<bool>(31, QMetaType::Bool, QMC::DefaultPropertyFlags, 0),
        // property 'senderMixPool'
        QtMocHelpers::PropertyData<int>(32, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'senderMsgOut'
        QtMocHelpers::PropertyData<int>(33, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'senderMsgIn'
        QtMocHelpers::PropertyData<int>(34, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'receiverPhase'
        QtMocHelpers::PropertyData<QString>(35, QMetaType::QString, QMC::DefaultPropertyFlags, 0),
        // property 'receiverOptLeaf'
        QtMocHelpers::PropertyData<int>(36, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'receiverAuthLeaf'
        QtMocHelpers::PropertyData<int>(37, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'receiverLeafCorrected'
        QtMocHelpers::PropertyData<bool>(38, QMetaType::Bool, QMC::DefaultPropertyFlags, 0),
        // property 'receiverPeers'
        QtMocHelpers::PropertyData<int>(39, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'receiverMixReady'
        QtMocHelpers::PropertyData<bool>(40, QMetaType::Bool, QMC::DefaultPropertyFlags, 0),
        // property 'receiverMixPool'
        QtMocHelpers::PropertyData<int>(41, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'receiverMsgOut'
        QtMocHelpers::PropertyData<int>(42, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
        // property 'receiverMsgIn'
        QtMocHelpers::PropertyData<int>(43, QMetaType::Int, QMC::DefaultPropertyFlags, 0),
    };
    QtMocHelpers::UintData qt_enums {
    };
    return QtMocHelpers::metaObjectData<MonitorBackend, qt_meta_tag_ZN14MonitorBackendE_t>(QMC::MetaObjectFlag{}, qt_stringData,
            qt_methods, qt_properties, qt_enums);
}
Q_CONSTINIT const QMetaObject MonitorBackend::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14MonitorBackendE_t>.stringdata,
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14MonitorBackendE_t>.data,
    qt_static_metacall,
    nullptr,
    qt_staticMetaObjectRelocatingContent<qt_meta_tag_ZN14MonitorBackendE_t>.metaTypes,
    nullptr
} };

void MonitorBackend::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<MonitorBackend *>(_o);
    if (_c == QMetaObject::InvokeMetaMethod) {
        switch (_id) {
        case 0: _t->stateChanged(); break;
        case 1: _t->onSequencerLine((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1]))); break;
        case 2: _t->onNodeLine((*reinterpret_cast<std::add_pointer_t<int>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2]))); break;
        case 3: _t->onChatLine((*reinterpret_cast<std::add_pointer_t<bool>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<QString>>(_a[2]))); break;
        case 4: _t->onBlockAgeTick(); break;
        case 5: _t->setStateDir((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast<std::add_pointer_t<bool>>(_a[2]))); break;
        case 6: _t->setStateDir((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1]))); break;
        case 7: _t->setRpcUrl((*reinterpret_cast<std::add_pointer_t<QString>>(_a[1]))); break;
        default: ;
        }
    }
    if (_c == QMetaObject::IndexOfMethod) {
        if (QtMocHelpers::indexOfMethod<void (MonitorBackend::*)()>(_a, &MonitorBackend::stateChanged, 0))
            return;
    }
    if (_c == QMetaObject::ReadProperty) {
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast<QString*>(_v) = _t->stateDir(); break;
        case 1: *reinterpret_cast<int*>(_v) = _t->blockId(); break;
        case 2: *reinterpret_cast<int*>(_v) = _t->blockAgeSecs(); break;
        case 3: *reinterpret_cast<int*>(_v) = _t->txValidated(); break;
        case 4: *reinterpret_cast<int*>(_v) = _t->txFailed(); break;
        case 5: *reinterpret_cast<int*>(_v) = _t->rpcBlockId(); break;
        case 6: *reinterpret_cast<bool*>(_v) = _t->rpcReachable(); break;
        case 7: *reinterpret_cast<QString*>(_v) = _t->mixNodeStates(); break;
        case 8: *reinterpret_cast<bool*>(_v) = _t->gifterMounted(); break;
        case 9: *reinterpret_cast<int*>(_v) = _t->gifterQueueDepth(); break;
        case 10: *reinterpret_cast<QString*>(_v) = _t->gifterStatus(); break;
        case 11: *reinterpret_cast<QString*>(_v) = _t->senderPhase(); break;
        case 12: *reinterpret_cast<int*>(_v) = _t->senderOptLeaf(); break;
        case 13: *reinterpret_cast<int*>(_v) = _t->senderAuthLeaf(); break;
        case 14: *reinterpret_cast<bool*>(_v) = _t->senderLeafCorrected(); break;
        case 15: *reinterpret_cast<int*>(_v) = _t->senderPeers(); break;
        case 16: *reinterpret_cast<bool*>(_v) = _t->senderMixReady(); break;
        case 17: *reinterpret_cast<int*>(_v) = _t->senderMixPool(); break;
        case 18: *reinterpret_cast<int*>(_v) = _t->senderMsgOut(); break;
        case 19: *reinterpret_cast<int*>(_v) = _t->senderMsgIn(); break;
        case 20: *reinterpret_cast<QString*>(_v) = _t->receiverPhase(); break;
        case 21: *reinterpret_cast<int*>(_v) = _t->receiverOptLeaf(); break;
        case 22: *reinterpret_cast<int*>(_v) = _t->receiverAuthLeaf(); break;
        case 23: *reinterpret_cast<bool*>(_v) = _t->receiverLeafCorrected(); break;
        case 24: *reinterpret_cast<int*>(_v) = _t->receiverPeers(); break;
        case 25: *reinterpret_cast<bool*>(_v) = _t->receiverMixReady(); break;
        case 26: *reinterpret_cast<int*>(_v) = _t->receiverMixPool(); break;
        case 27: *reinterpret_cast<int*>(_v) = _t->receiverMsgOut(); break;
        case 28: *reinterpret_cast<int*>(_v) = _t->receiverMsgIn(); break;
        default: break;
        }
    }
}

const QMetaObject *MonitorBackend::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *MonitorBackend::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_staticMetaObjectStaticContent<qt_meta_tag_ZN14MonitorBackendE_t>.strings))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int MonitorBackend::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 8)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 8;
    }
    if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 8)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 8;
    }
    if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 29;
    }
    return _id;
}

// SIGNAL 0
void MonitorBackend::stateChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 0, nullptr);
}
QT_WARNING_POP
