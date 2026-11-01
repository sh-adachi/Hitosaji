// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NutritionCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NutritionCore", targets: ["NutritionCore"])],
    targets: [
        .target(name: "NutritionCore", path: "Core"),
        .testTarget(name: "NutritionCoreTests", dependencies: ["NutritionCore"], path: "Tests/NutritionCoreTests")
    ]
)
