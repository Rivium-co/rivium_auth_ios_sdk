// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RiviumAuthExample",
    platforms: [.iOS(.v16), .macOS(.v13)],
    dependencies: [
        .package(name: "RiviumAuth", path: "../"),
    ],
    targets: [
        .executableTarget(
            name: "RiviumAuthExample",
            dependencies: [
                .product(name: "RiviumAuth", package: "RiviumAuth"),
            ],
            path: "RiviumAuthExample",
            exclude: ["Info.plist"]
        ),
    ]
)
