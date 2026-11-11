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
        .binaryTarget(name: "EmrtdCore", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.2/EmrtdCore.xcframework.zip", checksum: "4ae776ed97d643e8323c10fc77eedcd71539e206583fd4a8237d0adbd4110804"),
        .binaryTarget(name: "emrtdFFI", url: "https://github.com/ShareRing/emrtd/releases/download/v0.2.2/emrtdFFI.zip", checksum: "f45a4939adc5646b7ecd0f54c39e380f4210a45f413b9d6ec3e561b4952bdb46"),
    ]
)
