cmake_minimum_required(VERSION 3.16)
project(sim-monitor LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

option(ENABLE_HOST_MODE "Enable chat host mode (requires liblogos_core)" OFF)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Qml Quick Network)

set(MONITOR_SOURCES
    src/main.cpp
    src/MonitorBackend.h src/MonitorBackend.cpp
    src/LogTailer.h src/LogTailer.cpp
    src/LogParser.h src/LogParser.cpp
    src/ChainEventModel.h
    src/RpcClient.h src/RpcClient.cpp
)

if(ENABLE_HOST_MODE)
    list(APPEND MONITOR_SOURCES src/ChatHost.h src/ChatHost.cpp)
endif()

qt_add_executable(sim-monitor ${MONITOR_SOURCES})

qt_add_qml_module(sim-monitor
    URI SimMonitor
    VERSION 1.0
    QML_FILES src/qml/MonitorView.qml
    NO_RESOURCE_TARGET_PATH
)

target_link_libraries(sim-monitor PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::Network
)

if(ENABLE_HOST_MODE)
    target_compile_definitions(sim-monitor PRIVATE ENABLE_HOST_MODE=1)

    # liblogos_core — prefer BASECAMP_LIB (correct 2-arg API), fall back to LIBLOGOS_LIB
    if(DEFINED ENV{BASECAMP_LIB})
        target_link_directories(sim-monitor PRIVATE $ENV{BASECAMP_LIB})
        target_link_libraries(sim-monitor PRIVATE logos_core)
    elseif(DEFINED ENV{LIBLOGOS_LIB})
        target_link_directories(sim-monitor PRIVATE $ENV{LIBLOGOS_LIB})
        target_link_libraries(sim-monitor PRIVATE logos_core)
    else()
        message(WARNING "BASECAMP_LIB/LIBLOGOS_LIB not set — host mode will fail to link")
    endif()

    if(DEFINED ENV{LIBLOGOS_INCLUDE})
        target_include_directories(sim-monitor PRIVATE $ENV{LIBLOGOS_INCLUDE})
    else()
        message(WARNING "LIBLOGOS_INCLUDE not set — host mode headers not found")
    endif()

    find_package(Qt6 COMPONENTS RemoteObjects)
    if(Qt6RemoteObjects_FOUND)
        target_link_libraries(sim-monitor PRIVATE Qt6::RemoteObjects)
    endif()
endif()
