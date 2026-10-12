// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MyWeatherCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "MyWeatherCore", targets: ["MyWeatherCore"])
    ],
    targets: [
        .target(
            name: "MyWeatherCore",
            path: "MyWeather/Core"
        ),
        .testTarget(
            name: "MyWeatherCoreTests",
            dependencies: ["MyWeatherCore"],
            path: "MyWeatherTests"
        )
    ]
)
