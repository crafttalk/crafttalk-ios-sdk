// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "CraftTalk",
    products: [
        .library(
            name: "CraftTalk",
            targets: [
                "CraftTalk"
            ]
        )
    ],
    targets: [
        .target(
            name: "CraftTalk",
            path: "CTChat"
        )
    ]
)
