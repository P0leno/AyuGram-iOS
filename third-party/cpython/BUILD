load("@build_bazel_rules_apple//apple:apple.bzl", "apple_dynamic_xcframework_import")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_group")

apple_dynamic_xcframework_import(
    name = "PythonXCFramework",
    xcframework_imports = glob(
        ["Python.xcframework/**"],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

apple_resource_group(
    name = "PythonStdlibResources",
    structured_resources = glob(
        ["python/**"],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

alias(
    name = "PythonExtResources",
    actual = select({
        "@build_bazel_rules_apple//apple:ios_arm64": "//third-party/cpython/ExtResources/iphoneos:Resources",
        "//build-system:ios_sim_arm64": "//third-party/cpython/ExtResources/iphonesimulator_arm64:Resources",
        "@build_bazel_rules_apple//apple:ios_x86_64": "//third-party/cpython/ExtResources/iphonesimulator_x86_64:Resources",
        "//conditions:default": "//third-party/cpython/ExtResources/iphoneos:Resources",
    }),
    visibility = ["//visibility:public"],
)
