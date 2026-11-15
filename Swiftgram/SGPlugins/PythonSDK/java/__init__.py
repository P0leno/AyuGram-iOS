"""Pure-Python / iOS compatibility shims for Android/Java Xposed hooks."""


class JavaNotSupportedError(RuntimeError):
    """Raised when an Android plugin invokes JVM/ART class reflection unsupported on iOS."""


def _report_jvm_usage(api_name: str, detail: str = "") -> None:
    try:
        import _ayu_runtime_host

        msg = f"Unsupported Android/Java API `{api_name}`"
        if detail:
            msg += f" ({detail})"
        msg += ": Android ART/Xposed reflection is not available on iOS."
        _ayu_runtime_host.record_current_incompatibility(msg)
    except Exception:
        pass


def jclass(class_name: str):
    """Stub replacing `from java import jclass` with an explicit iOS diagnostic."""
    _report_jvm_usage("java.jclass", class_name)
    raise JavaNotSupportedError(
        f"Cannot resolve Java class '{class_name}' on iOS. "
        "Plugins relying on Android Java/Telegram Xposed hooks cannot run on iOS; "
        "only pure-Python plugins using standard exteraCompat APIs are supported."
    )


def dynamic_proxy(*_interfaces):
    """Stub replacing `java.dynamic_proxy`."""
    _report_jvm_usage("java.dynamic_proxy")
    raise JavaNotSupportedError("java.dynamic_proxy is Android-only and unsupported on iOS.")


def cast(_target_type, value):
    """Stub replacing `java.cast`."""
    _report_jvm_usage("java.cast")
    return value


def jarray(_element_type):
    """Stub replacing `java.jarray`."""
    _report_jvm_usage("java.jarray")
    raise JavaNotSupportedError("java.jarray is Android-only and unsupported on iOS.")
