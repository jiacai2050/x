// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Qianliyan",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Qianliyan", targets: ["Qianliyan"])
    ],
    targets: [
        .target(
            name: "CQianliyan",
            path: "Sources/CQianliyan",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Qianliyan",
            dependencies: ["CQianliyan"],
            path: "Sources/Qianliyan",
            linkerSettings: [
                .unsafeFlags([
                    "-L../zig-out/lib",
                    "-lqianliyan"
                ])
            ]
        )
    ]
)
