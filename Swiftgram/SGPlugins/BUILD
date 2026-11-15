load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_group")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

apple_resource_group(
    name = "SGPluginsResources",
    structured_resources = glob(["PythonSDK/**"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "SGPlugins",
    module_name = "SGPlugins",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Display:Display",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/UndoUI:UndoUI",
        "//Swiftgram/SGStrings:SGStrings",
        "//Swiftgram/SGPluginBridge:SGPluginBridge",
        "//Swiftgram/CPluginPython:CPluginPython",
    ],
    visibility = [
        "//visibility:public",
    ],
)
