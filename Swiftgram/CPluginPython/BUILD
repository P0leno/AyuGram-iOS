load("@rules_cc//cc:objc_library.bzl", "objc_library")

objc_library(
    name = "CPluginPython",
    enable_modules = True,
    module_name = "CPluginPython",
    srcs = [
        "Sources/AyuPythonRuntime.m",
    ],
    hdrs = [
        "PublicHeaders/AyuPythonRuntime.h",
    ],
    includes = [
        "PublicHeaders",
    ],
    data = [
        "//third-party/cpython:PythonStdlibResources",
        "//third-party/cpython:PythonExtResources",
    ],
    sdk_frameworks = [
        "Foundation",
    ],
    sdk_dylibs = [
        "sqlite3",
        "z",
    ],
    deps = [
        "//third-party/cpython:PythonXCFramework",
    ],
    visibility = [
        "//visibility:public",
    ],
)
