// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BetoDicta",
    platforms: [.macOS(.v14)],
    targets: [
        // Puente ObjC mínimo: @try/@catch para NSException (Swift no las atrapa).
        .target(
            name: "BDObjC",
            path: "Sources/BDObjC",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "BetoDicta",
            dependencies: ["BDObjC"],
            path: "Sources/BetoDicta"
        )
    ]
)
