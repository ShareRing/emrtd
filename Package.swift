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
        .binaryTarget(name: "EmrtdCore", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.0/EmrtdCore.xcframework.zip", checksum: "463e8095b7bca9cf6f92c666632c8c0e7a5ba54e1eda356d585ed97c2933baf0"),
        .binaryTarget(name: "emrtdFFI", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.0/emrtdFFI.zip", checksum: "0cdf034b4959e9f19027e5e12d2bab8468b05621444b5bf54657793318102f4d"),
    ]
)
