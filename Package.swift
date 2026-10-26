// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SelAtRans",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SelAtRans", targets: ["SelAtRans"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5")],
    targets: [
        .target(name: "TranslationCore"),
        .executableTarget(name: "SelAtRans", dependencies: ["TranslationCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "CoreChecks", dependencies: ["TranslationCore"], path: "Tests/CoreChecks")
    ]
)
