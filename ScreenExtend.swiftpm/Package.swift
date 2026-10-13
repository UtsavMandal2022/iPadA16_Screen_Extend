// swift-tools-version: 5.9

// Swift Playgrounds app package. Open this folder in Swift Playgrounds on the iPad
// (or in Xcode on a Mac) and press Run.
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Screen Extend",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Screen Extend",
            targets: ["AppModule"],
            bundleIdentifier: "com.utsav.screenextend",
            teamIdentifier: "",
            displayVersion: "0.2",
            bundleVersion: "2",
            appIcon: .placeholder(icon: .tv),
            accentColor: .presetColor(.purple),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown
            ],
            appCategory: .utilities
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
