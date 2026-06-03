#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCommandLineParser>
#include <QDir>
#include "MonitorBackend.h"

#ifdef ENABLE_HOST_MODE
#include "ChatHost.h"
#endif

int main(int argc, char* argv[]) {
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    QGuiApplication app(argc, argv);
    app.setApplicationName("sim-monitor");

    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({{"d", "state-dir"}, "Path to .sim_state directory", "dir"});
    parser.addOption({{"r", "rpc-url"}, "Sequencer JSON-RPC URL", "url"});
    parser.addOption({"replay", "Start from beginning of logs instead of tail"});
#ifdef ENABLE_HOST_MODE
    parser.addOption({"host-chat", "Enable chat host mode (load chat_module + deps)"});
    parser.addOption({"chat-config", "Path to chat config JSON file", "file"});
#endif
    parser.process(app);

    QString stateDir = parser.value("state-dir");
    if (stateDir.isEmpty())
        stateDir = QStringLiteral("simulations/mix_lez_chat/.sim_state");

    MonitorBackend backend;

#ifdef ENABLE_HOST_MODE
    ChatHost* chatHost = nullptr;
    bool hostMode = parser.isSet("host-chat");

    if (hostMode) {
        chatHost = new ChatHost(&backend);

        QString userDir = qEnvironmentVariable("LOGOS_USER_DIR");
        if (userDir.isEmpty()) {
            qWarning() << "LOGOS_USER_DIR not set — chat host mode needs staged modules";
        } else {
            QString modulesDir = QDir(userDir).filePath("modules");
            QString dataDir = QDir(userDir).filePath("module_data");
            QDir().mkpath(dataDir);

            if (!chatHost->loadModules(modulesDir, dataDir)) {
                qWarning() << "Failed to load chat modules — host mode disabled";
                hostMode = false;
            }
        }
    }
#endif

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("monitor", &backend);
    engine.rootContext()->setContextProperty("chainEvents", backend.chainEventModel());

#ifdef ENABLE_HOST_MODE
    engine.rootContext()->setContextProperty("chatHost", chatHost);
    engine.rootContext()->setContextProperty("hostModeEnabled",
        QVariant(hostMode && chatHost != nullptr));
#else
    engine.rootContext()->setContextProperty("chatHost", QVariant());
    engine.rootContext()->setContextProperty("hostModeEnabled", QVariant(false));
#endif

    engine.load(QUrl("qrc:/src/qml/MonitorView.qml"));
    if (engine.rootObjects().isEmpty()) return -1;

    if (!stateDir.isEmpty())
        backend.setStateDir(stateDir, parser.isSet("replay"));

    QString rpcUrl = parser.value("rpc-url");
    if (rpcUrl.isEmpty()) rpcUrl = qEnvironmentVariable("SIM_SEQ_RPC");
    if (!rpcUrl.isEmpty()) backend.setRpcUrl(rpcUrl);

    qDebug() << "Starting event loop...";
    int rc = app.exec();
    qDebug() << "Event loop exited with" << rc;
    return rc;
}
