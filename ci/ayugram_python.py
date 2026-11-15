"""Prepare embedded CPython 3.13 iOS runtime, pruned stdlib, extension frameworks, and pure-Python wheels."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

PYTHON_APPLE_SUPPORT_URL = (
    "https://github.com/beeware/Python-Apple-support/releases/download/"
    "3.13-b18/Python-3.13-iOS-support.b18.tar.gz"
)
PYTHON_APPLE_SUPPORT_SHA256 = (
    "d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d"
)

FRAMEWORK_PREFIX = "PyExt_"
FRAMEWORK_BUNDLE_ID_PREFIX = "io.ayugram.pyext."
MIN_IOS_VERSION = "13.0"
PYTHON_VERSION_DIR = "python3.13"


@dataclass(frozen=True)
class WheelSpec:
    """Pinned pure-Python wheel metadata verified by SHA-256."""

    name: str
    filename: str
    url: str
    sha256: str


PURE_PYTHON_WHEELS: tuple[WheelSpec, ...] = (
    WheelSpec(
        name="requests",
        filename="requests-2.34.2-py3-none-any.whl",
        url=(
            "https://files.pythonhosted.org/packages/a0/f4/"
            "c67b0b3f1b9245e8d266f0f112c500d50e5b4e83cb6f3b71b6528104182a/"
            "requests-2.34.2-py3-none-any.whl"
        ),
        sha256="2a0d60c172f83ac6ab31e4554906c0f3b3588d37b5cb939b1c061f4907e278e0",
    ),
    WheelSpec(
        name="urllib3",
        filename="urllib3-2.8.0-py3-none-any.whl",
        url=(
            "https://files.pythonhosted.org/packages/92/9d/"
            "c4e665119135114480843e7ab388fa94d8480650450e6f8e26b70d323a4c/"
            "urllib3-2.8.0-py3-none-any.whl"
        ),
        sha256="0cf3cae568d36aa9576b28dfb35f11328f1cb974ca7647d9475ebb86c75ac6e3",
    ),
    WheelSpec(
        name="certifi",
        filename="certifi-2026.10.23-py3-none-any.whl",
        url=(
            "https://files.pythonhosted.org/packages/32/d1/"
            "a3652fe2c19134d0d15922177821d863cbd7e842d53a21bbe7e8e3a1b5ac/"
            "certifi-2026.10.23-py3-none-any.whl"
        ),
        sha256="e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1",
    ),
    WheelSpec(
        name="idna",
        filename="idna-3.20-py3-none-any.whl",
        url=(
            "https://files.pythonhosted.org/packages/58/a2/"
            "bb081bab032533a855d44de1d56f8e8426114ff1ba5d1f07a438a0a654f8/"
            "idna-3.20-py3-none-any.whl"
        ),
        sha256="ab7ae7122974553370f0bdb919e1a960b2cd1bc1ef0276416d896db81c14582c",
    ),
    WheelSpec(
        name="charset-normalizer",
        filename="charset_normalizer-3.5.2-py3-none-any.whl",
        url=(
            "https://files.pythonhosted.org/packages/fc/ad/"
            "d07d7862a62ffa6d79d68074d14823243dd235a77c45262acbf6adeb28bf/"
            "charset_normalizer-3.5.2-py3-none-any.whl"
        ),
        sha256="b6b751274acb69d77b3323d6b7dbaa3c7fdfc1eb829b7eb61d262f32e1af9685",
    ),
)

STRIP_STDLIB_PREFIXES: tuple[str, ...] = (
    "test/",
    "idlelib/",
    "tkinter/",
    "turtledemo/",
    "ensurepip/",
    "pydoc_data/",
    "__phello__/",
    "venv/",
)

STRIP_STDLIB_FILES: frozenset[str] = frozenset({
    "turtle.py",
    "__hello__.py",
})

DROP_EXTENSIONS: frozenset[str] = frozenset({
    "_ctypes_test",
    "_testbuffer",
    "_testcapi",
    "_testclinic",
    "_testclinic_limited",
    "_testexternalinspection",
    "_testimportmultiple",
    "_testinternalcapi",
    "_testlimitedcapi",
    "_testmultiphase",
    "_testsinglephase",
    "_xxtestfuzz",
    "xxlimited",
    "xxlimited_35",
    "xxsubtype",
    "_interpchannels",
    "_interpqueues",
    "_interpreters",
})

SLICE_SOURCES: tuple[tuple[str, str, str, str], ...] = (
    ("iphoneos", "ios-arm64/lib-arm64", "iphoneos", "iPhoneOS"),
    (
        "iphonesimulator_arm64",
        "ios-arm64_x86_64-simulator/lib-arm64",
        "iphonesimulator",
        "iPhoneSimulator",
    ),
    (
        "iphonesimulator_x86_64",
        "ios-arm64_x86_64-simulator/lib-x86_64",
        "iphonesimulator",
        "iPhoneSimulator",
    ),
)


def sha256_file(path: Path) -> str:
    """Compute hex SHA-256 digest for a file."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().lower()


def _verify_sha256(path: Path, expected: str, label: str) -> None:
    actual = sha256_file(path)
    if actual != expected.lower():
        raise ValueError(
            f"SHA-256 mismatch for {label} ({path}): expected {expected}, got {actual}"
        )


def download_verified(
    url: str,
    dest_path: Path,
    expected_sha256: str,
    label: str,
) -> Path:
    """Download URL to dest_path atomically and verify SHA-256, reusing valid cached files."""
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    if dest_path.is_file():
        try:
            _verify_sha256(dest_path, expected_sha256, label)
            return dest_path
        except ValueError:
            dest_path.unlink(missing_ok=True)

    tmp_path = dest_path.with_suffix(dest_path.suffix + ".tmp")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "AyuGram-iOS-CI/1.0 (+https://github.com/P0leno/AyuGram-iOS)"},
    )
    with urllib.request.urlopen(request, timeout=180) as response, tmp_path.open("wb") as out:
        shutil.copyfileobj(response, out)

    _verify_sha256(tmp_path, expected_sha256, label)
    tmp_path.replace(dest_path)
    return dest_path


def _resolve_install_name_tool() -> str | None:
    if sys.platform != "darwin":
        return None
    return shutil.which("install_name_tool")


def _resolve_codesign() -> str | None:
    if sys.platform != "darwin":
        return None
    return shutil.which("codesign")


def _safe_tar_member_path(base_dir: Path, rel_path: str) -> Path:
    resolved_base = base_dir.resolve()
    target = (resolved_base / rel_path).resolve()
    target.relative_to(resolved_base)
    return target


def _write_file_bytes(dest: Path, data: bytes, executable: bool = False) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    mode = 0o755 if executable else 0o644
    try:
        os.chmod(dest, mode)
    except OSError:
        pass


def _extract_python_xcframework(tf: tarfile.TarFile, xcfw_dest: Path) -> None:
    """Extract slim Python.xcframework keeping Info.plist and device/simulator Python.framework."""
    if xcfw_dest.exists():
        shutil.rmtree(xcfw_dest)
    xcfw_dest.mkdir(parents=True, exist_ok=True)

    allowed_prefixes = (
        "Python.xcframework/Info.plist",
        "Python.xcframework/ios-arm64/Python.framework/",
        "Python.xcframework/ios-arm64_x86_64-simulator/Python.framework/",
    )

    for member in tf.getmembers():
        if not member.isfile():
            continue
        if member.name != allowed_prefixes[0] and not member.name.startswith(allowed_prefixes[1:]):
            continue
        rel = member.name[len("Python.xcframework/"):]
        out_path = _safe_tar_member_path(xcfw_dest, rel)
        extracted = tf.extractfile(member)
        if extracted is None:
            continue
        is_exec = bool(member.mode & stat.S_IXUSR) or out_path.name == "Python"
        _write_file_bytes(out_path, extracted.read(), executable=is_exec)


def _should_keep_stdlib_relpath(rel_path: str) -> bool:
    if not rel_path or rel_path in STRIP_STDLIB_FILES:
        return False
    if any(rel_path.startswith(prefix) for prefix in STRIP_STDLIB_PREFIXES):
        return False
    if "/__pycache__/" in rel_path or rel_path.startswith("__pycache__/") or rel_path.endswith((".pyc", ".pyo")):
        return False
    if rel_path.startswith("site-packages/") and rel_path != "site-packages/README.txt":
        return False
    return True


def _extract_stdlib(tf: tarfile.TarFile, python_dest: Path) -> Path:
    """Extract pruned Python 3.13 standard library + slice _sysconfigdata files."""
    if python_dest.exists():
        shutil.rmtree(python_dest)

    stdlib_dir = python_dest / "lib" / PYTHON_VERSION_DIR
    stdlib_dir.mkdir(parents=True, exist_ok=True)
    lib_dynload_dir = stdlib_dir / "lib-dynload"
    lib_dynload_dir.mkdir(parents=True, exist_ok=True)
    site_packages_dir = python_dest / "site-packages"
    site_packages_dir.mkdir(parents=True, exist_ok=True)

    prefix = f"Python.xcframework/lib/{PYTHON_VERSION_DIR}/"
    for member in tf.getmembers():
        if not member.isfile() or not member.name.startswith(prefix):
            continue
        rel = member.name[len(prefix):]
        if not _should_keep_stdlib_relpath(rel):
            continue
        out_path = _safe_tar_member_path(stdlib_dir, rel)
        extracted = tf.extractfile(member)
        if extracted is None:
            continue
        _write_file_bytes(out_path, extracted.read(), executable=False)

    # Include per-architecture _sysconfigdata files needed by sysconfig/platform.
    for _, lib_subpath, _, _ in SLICE_SOURCES:
        sysconfig_prefix = f"Python.xcframework/{lib_subpath}/{PYTHON_VERSION_DIR}/"
        for member in tf.getmembers():
            if not member.isfile() or not member.name.startswith(sysconfig_prefix):
                continue
            rel = member.name[len(sysconfig_prefix):]
            if not rel.startswith("_sysconfigdata__"):
                continue
            out_path = _safe_tar_member_path(stdlib_dir, rel)
            extracted = tf.extractfile(member)
            if extracted is None:
                continue
            _write_file_bytes(out_path, extracted.read(), executable=False)

    return python_dest


def _framework_name_for_module(module_name: str) -> str:
    return f"{FRAMEWORK_PREFIX}{module_name}"


def _build_framework_bundle(
    so_bytes: bytes,
    module_name: str,
    platform_family: str,
    frameworks_dir: Path,
    origin_fwork_relpath: str,
    install_name_tool_path: str | None,
    codesign_path: str | None = None,
) -> Path:
    """Create a dynamic framework wrapper around a CPython .so extension for iOS dlopen."""
    fw_name = _framework_name_for_module(module_name)
    fw_dir = frameworks_dir / f"{fw_name}.framework"
    fw_dir.mkdir(parents=True, exist_ok=True)

    bin_path = fw_dir / fw_name
    _write_file_bytes(bin_path, so_bytes, executable=True)

    if codesign_path and install_name_tool_path:
        # Simulator prebuilt slices carry an ad-hoc signature; strip it before rewriting install name.
        subprocess.run(
            [codesign_path, "--remove-signature", str(bin_path)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    if install_name_tool_path:
        subprocess.run(
            [install_name_tool_path, "-id", f"@rpath/{fw_name}.framework/{fw_name}", str(bin_path)],
            check=True,
        )

    bundle_id = FRAMEWORK_BUNDLE_ID_PREFIX + module_name.replace("_", "-")
    plist_data = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": fw_name,
        "CFBundleIdentifier": bundle_id,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": fw_name,
        "CFBundlePackageType": "FMWK",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "CFBundleSupportedPlatforms": [platform_family],
        "MinimumOSVersion": MIN_IOS_VERSION,
    }
    with (fw_dir / "Info.plist").open("wb") as handle:
        plistlib.dump(plist_data, handle)

    (fw_dir / f"{fw_name}.origin").write_text(origin_fwork_relpath + "\n", encoding="utf-8")
    return fw_dir


def _clean_generated_frameworks(ext_arch_dir: Path) -> None:
    """Remove generated Frameworks dir inside ExtResources/<arch> without deleting its BUILD file."""
    frameworks_dir = ext_arch_dir / "Frameworks"
    if frameworks_dir.exists():
        shutil.rmtree(frameworks_dir)
    frameworks_dir.mkdir(parents=True, exist_ok=True)


def _process_dynload_extensions(
    tf: tarfile.TarFile,
    lib_dynload_dir: Path,
    ext_resources_dir: Path,
) -> list[str]:
    """Extract kept C extension modules into per-slice Frameworks and write .fwork placeholders."""
    install_name_tool_path = _resolve_install_name_tool()
    codesign_path = _resolve_codesign()
    discovered_modules: set[str] = set()

    for arch_key, lib_subpath, platform_tag, platform_family in SLICE_SOURCES:
        arch_dir = ext_resources_dir / arch_key
        _clean_generated_frameworks(arch_dir)
        frameworks_dir = arch_dir / "Frameworks"

        dynload_prefix = f"Python.xcframework/{lib_subpath}/{PYTHON_VERSION_DIR}/lib-dynload/"
        for member in tf.getmembers():
            if not member.isfile() or not member.name.startswith(dynload_prefix):
                continue
            filename = Path(member.name).name
            if not filename.endswith(".so"):
                continue
            module_name = filename.split(".", 1)[0]
            if module_name in DROP_EXTENSIONS:
                continue

            fwork_filename = filename[:-3] + ".fwork"
            fwork_relpath = f"python/lib/{PYTHON_VERSION_DIR}/lib-dynload/{fwork_filename}"
            fw_name = _framework_name_for_module(module_name)

            extracted = tf.extractfile(member)
            if extracted is None:
                continue
            _build_framework_bundle(
                so_bytes=extracted.read(),
                module_name=module_name,
                platform_family=platform_family,
                frameworks_dir=frameworks_dir,
                origin_fwork_relpath=fwork_relpath,
                install_name_tool_path=install_name_tool_path,
                codesign_path=codesign_path,
            )

            fwork_path = lib_dynload_dir / fwork_filename
            fwork_path.write_text(f"Frameworks/{fw_name}.framework/{fw_name}\n", encoding="utf-8")
            discovered_modules.add(module_name)

    return sorted(discovered_modules)


def _unpack_pure_python_wheel(wheel_path: Path, site_packages_dir: Path) -> None:
    """Extract pure-Python wheel payload into site-packages without bytecode caches."""
    resolved_sp = site_packages_dir.resolve()
    with zipfile.ZipFile(wheel_path, "r") as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            rel = info.filename.replace("\\", "/")
            if "/__pycache__/" in rel or rel.endswith((".pyc", ".pyo")):
                continue
            out_path = (resolved_sp / rel).resolve()
            out_path.relative_to(resolved_sp)
            _write_file_bytes(out_path, zf.read(info.filename), executable=False)


def expected_stamp_payload(wheels: tuple[WheelSpec, ...] = PURE_PYTHON_WHEELS) -> dict:
    """Build deterministic version stamp metadata to skip redundant CI extracts."""
    return {
        "python_sha256": PYTHON_APPLE_SUPPORT_SHA256,
        "drop_extensions": sorted(DROP_EXTENSIONS),
        "wheels": {w.name: w.sha256 for w in wheels},
    }


def is_prepared(source_root: Path, cpython_rel: Path = Path("third-party/cpython")) -> bool:
    """Return True if third-party/cpython already contains matching verified artifacts."""
    cpython_dir = Path(source_root) / cpython_rel
    stamp_path = cpython_dir / ".prepared_version"
    required_paths = (
        cpython_dir / "Python.xcframework" / "Info.plist",
        cpython_dir / "python" / "lib" / PYTHON_VERSION_DIR / "os.py",
        cpython_dir / "python" / "site-packages" / "requests" / "__init__.py",
        cpython_dir / "ExtResources" / "iphoneos" / "Frameworks" / "PyExt__json.framework" / "Info.plist",
    )
    if not stamp_path.is_file() or not all(p.is_file() for p in required_paths):
        return False
    try:
        current = json.loads(stamp_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return current == expected_stamp_payload()


def prepare_python(
    source_root: Path,
    python_archive: Path | None = None,
    cache_dir: Path | None = None,
    wheels: tuple[WheelSpec, ...] = PURE_PYTHON_WHEELS,
    force: bool = False,
) -> dict:
    """Download/verify CPython iOS + pure-Python wheels and populate third-party/cpython."""
    source_root = Path(source_root)
    cpython_dir = source_root / "third-party" / "cpython"
    cpython_dir.mkdir(parents=True, exist_ok=True)

    if not force and wheels == PURE_PYTHON_WHEELS and is_prepared(source_root):
        return {"skipped": True, "cpython_dir": str(cpython_dir)}

    resolved_cache = (
        Path(cache_dir)
        if cache_dir
        else Path(
            os.environ.get(
                "AYUGRAM_PYTHON_CACHE_DIR",
                str(source_root / ".cache" / "python-ios"),
            )
        )
    )
    resolved_cache.mkdir(parents=True, exist_ok=True)

    env_archive = os.environ.get("AYUGRAM_PYTHON_ARCHIVE", "").strip()
    archive_override = python_archive or (Path(env_archive) if env_archive else None)
    if archive_override is not None:
        archive_path = Path(archive_override)
        _verify_sha256(archive_path, PYTHON_APPLE_SUPPORT_SHA256, "Python-3.13-iOS-support")
    else:
        archive_path = download_verified(
            PYTHON_APPLE_SUPPORT_URL,
            resolved_cache / "Python-3.13-iOS-support.b18.tar.gz",
            PYTHON_APPLE_SUPPORT_SHA256,
            "Python-3.13-iOS-support",
        )

    wheel_paths: list[Path] = []
    for spec in wheels:
        local_candidate = resolved_cache / spec.filename
        if archive_override is not None and local_candidate.is_file():
            _verify_sha256(local_candidate, spec.sha256, spec.name)
            wheel_paths.append(local_candidate)
        else:
            wheel_paths.append(
                download_verified(spec.url, local_candidate, spec.sha256, spec.name)
            )

    xcfw_dest = cpython_dir / "Python.xcframework"
    python_dest = cpython_dir / "python"
    ext_resources_dir = cpython_dir / "ExtResources"

    with tarfile.open(archive_path, "r:gz") as tf:
        _extract_python_xcframework(tf, xcfw_dest)
        _extract_stdlib(tf, python_dest)
        kept_modules = _process_dynload_extensions(
            tf,
            python_dest / "lib" / PYTHON_VERSION_DIR / "lib-dynload",
            ext_resources_dir,
        )

    site_packages_dir = python_dest / "site-packages"
    for wp in wheel_paths:
        _unpack_pure_python_wheel(wp, site_packages_dir)

    stamp_path = cpython_dir / ".prepared_version"
    stamp_path.write_text(
        json.dumps(expected_stamp_payload(wheels), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return {
        "skipped": False,
        "cpython_dir": str(cpython_dir),
        "kept_modules": kept_modules,
        "wheels": [w.name for w in wheels],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prepare embedded CPython 3.13 for AyuGram-iOS.")
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--python-archive", type=Path, default=None)
    parser.add_argument("--cache-dir", type=Path, default=None)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)

    result = prepare_python(
        source_root=args.source,
        python_archive=args.python_archive,
        cache_dir=args.cache_dir,
        force=args.force,
    )
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
