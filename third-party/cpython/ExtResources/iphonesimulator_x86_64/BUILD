load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_group")

apple_resource_group(
    name = "Resources",
    structured_resources = glob(
        ["Frameworks/**"],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)
