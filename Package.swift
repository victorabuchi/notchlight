// swift-tools-version:5.9
import PackageDescription

// NotchShape: the curved notch shape Notchlight draws its island, Light and Tray with, free to use.
let package = Package(
    name: "NotchShape",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "NotchShape", targets: ["NotchShape"])],
    targets: [.target(name: "NotchShape")]
)
