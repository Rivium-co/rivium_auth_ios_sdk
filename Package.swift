// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "RiviumAuth",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "RiviumAuth",
            targets: ["RiviumAuth"]
        ),
    ],
    targets: [
        .target(
            name: "RiviumAuth",
            path: "Sources/RiviumAuth"
        ),
        .testTarget(
            name: "RiviumAuthTests",
            dependencies: ["RiviumAuth"],
            path: "Tests/RiviumAuthTests"
        ),
    ]
)
