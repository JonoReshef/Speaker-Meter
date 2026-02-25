// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VolumeMeter",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "VolumeMeter",
            path: "Sources/VolumeMeter",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist"
                ])
            ]
        )
    ]
)
