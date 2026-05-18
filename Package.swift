// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoneyMCPServer",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "MoneyMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/MoneyMCPServer"
        ),
        .testTarget(
            name: "MoneyMCPServerTests",
            dependencies: ["MoneyMCPServer"],
            path: "Tests/MoneyMCPServerTests",
            resources: [.copy("Resources")]
        ),
    ]
)
