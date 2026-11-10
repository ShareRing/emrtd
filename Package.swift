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
        .binaryTarget(name: "EmrtdCore", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.1/EmrtdCore.xcframework.zip", checksum: "39c03b10a1b8b86d132a4cbf79725f083c44158daae1e824feac29fc02ccb821"),
        .binaryTarget(name: "emrtdFFI", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.1/emrtdFFI.zip", checksum: "b226f6171078378e7b39898c6b8d2471005b75fbe1d781e535ac2b5eb20aed91"),
    ]
)
