// swift-tools-version: 5.9
import PackageDescription

// emrtd for iOS, generated for github.com/ShareRing/emrtd by the release workflow. Do not edit
// it there: every release overwrites it, with URLs and checksums of the archives built for that
// tag.
//
// Both targets are prebuilt. EmrtdCore is the CoreNFC transport and scanner, emrtdFFI the core
// it drives, for arm64 devices and for the simulator on Apple silicon and Intel.
let package = Package(
    name: "EmrtdCore",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "EmrtdCore", targets: ["EmrtdCore", "emrtdFFI"])
    ],
    targets: [
        .binaryTarget(name: "EmrtdCore", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.0/EmrtdCore.xcframework.zip", checksum: "f13dfef42e2bdf59e32520af47f5085496ac98e7f3ece42a8dbd1f1692356d6e"),
        .binaryTarget(name: "emrtdFFI", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.0/emrtdFFI.zip", checksum: "a38a3609b51075e898ef26be3102a598aebe48ceaf65790c24f530d42e90776d"),
    ]
)
