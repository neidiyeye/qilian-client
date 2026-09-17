// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DbaoIOSVPNPlugin",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(name: "DbaoIOSVPNPlugin", targets: ["DbaoIOSVPNPlugin"]),
    ],
    targets: [
        .target(
            name: "DbaoIOSVPNPlugin",
            path: "Sources",
            exclude: [
                // DCloud 插件模板需要复制到 HBuilderX 原生插件工程后再编译，本 Swift Package 不直接依赖 DCloud SDK。
                "App/DbaoUniPluginBridge.swift.template",
            ]
        ),
        .testTarget(
            name: "DbaoIOSVPNPluginTests",
            dependencies: ["DbaoIOSVPNPlugin"],
            path: "Tests"
        ),
    ]
)
