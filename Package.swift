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
        .binaryTarget(name: "EmrtdCore", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.3/EmrtdCore.xcframework.zip", checksum: "24364877154b736913e17ea81bb5841f8df6d0498dc611bb7e21eab6e8ed123e"),
        .binaryTarget(name: "emrtdFFI", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.3/emrtdFFI.zip", checksum: "0817578cd6bc0cc77003ef669d905cafd4e32270bcbe9f1f15c774ec03598d44"),
    ]
)
