import hashlib
import io
import os
import plistlib
import sys
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import ayugram_python


def _make_synthetic_wheel(dest: Path, package: str, code: str) -> ayugram_python.WheelSpec:
    with zipfile.ZipFile(dest, "w") as zf:
        zf.writestr(f"{package}/__init__.py", code)
        zf.writestr(f"{package}/__pycache__/ignored.pyc", b"pyc")
    sha = hashlib.sha256(dest.read_bytes()).hexdigest()
    return ayugram_python.WheelSpec(name=package, filename=dest.name, url="https://example.invalid/" + dest.name, sha256=sha)


def _add_tar_bytes(tf: tarfile.TarFile, name: str, data: bytes) -> None:
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    info.mode = 0o644
    tf.addfile(info, io.BytesIO(data))


def _make_synthetic_python_archive(dest: Path) -> str:
    with tarfile.open(dest, "w:gz") as tf:
        _add_tar_bytes(tf, "Python.xcframework/Info.plist", b"<plist/>")
        _add_tar_bytes(tf, "Python.xcframework/ios-arm64/Python.framework/Python", b"MACH0")
        _add_tar_bytes(tf, "Python.xcframework/ios-arm64/Python.framework/Headers/Python.h", b"/* h */")
        _add_tar_bytes(tf, "Python.xcframework/ios-arm64_x86_64-simulator/Python.framework/Python", b"MACH0SIM")
        _add_tar_bytes(tf, "Python.xcframework/lib/python3.13/os.py", b"# os")
        _add_tar_bytes(tf, "Python.xcframework/lib/python3.13/test/test_bad.py", b"# strip")
        _add_tar_bytes(tf, "Python.xcframework/lib/python3.13/tkinter/__init__.py", b"# strip")
        _add_tar_bytes(tf, "Python.xcframework/ios-arm64/lib-arm64/python3.13/_sysconfigdata__ios_arm64-iphoneos.py", b"build_time_vars={}")
        _add_tar_bytes(tf, "Python.xcframework/ios-arm64_x86_64-simulator/lib-arm64/python3.13/_sysconfigdata__ios_arm64-iphonesimulator.py", b"build_time_vars={}")
        _add_tar_bytes(tf, "Python.xcframework/ios-arm64_x86_64-simulator/lib-x86_64/python3.13/_sysconfigdata__ios_x86_64-iphonesimulator.py", b"build_time_vars={}")
        for mod, data in [("_json", b"JSONSO"), ("_ssl", b"SSLSO"), ("_testcapi", b"DROPME")]:
            _add_tar_bytes(tf, f"Python.xcframework/ios-arm64/lib-arm64/python3.13/lib-dynload/{mod}.cpython-313-iphoneos.so", data)
            _add_tar_bytes(tf, f"Python.xcframework/ios-arm64_x86_64-simulator/lib-arm64/python3.13/lib-dynload/{mod}.cpython-313-iphonesimulator.so", data + b"A")
            _add_tar_bytes(tf, f"Python.xcframework/ios-arm64_x86_64-simulator/lib-x86_64/python3.13/lib-dynload/{mod}.cpython-313-iphonesimulator.so", data + b"X")
    return hashlib.sha256(dest.read_bytes()).hexdigest()


class TestPythonBundlePreparation(unittest.TestCase):
    def test_synthetic_prepare_and_caching(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            cache = Path(tmp) / "cache"
            cache.mkdir(parents=True)
            for arch in ("iphoneos", "iphonesimulator_arm64", "iphonesimulator_x86_64"):
                b = root / "third-party" / "cpython" / "ExtResources" / arch / "BUILD"
                b.parent.mkdir(parents=True, exist_ok=True)
                b.write_text("# keep\n", encoding="utf-8")

            archive = Path(tmp) / "py.tar.gz"
            archive_sha = _make_synthetic_python_archive(archive)
            wheel = _make_synthetic_wheel(cache / "requests-2.34.2-py3-none-any.whl", "requests", "VERSION='1'\n")

            with mock.patch.object(ayugram_python, "PYTHON_APPLE_SUPPORT_SHA256", archive_sha):
                result = ayugram_python.prepare_python(
                    source_root=root,
                    python_archive=archive,
                    cache_dir=cache,
                    wheels=(wheel,),
                    force=True,
                )

            self.assertFalse(result["skipped"])
            self.assertEqual(result["kept_modules"], ["_json", "_ssl"])

            cpython = root / "third-party" / "cpython"
            self.assertTrue((cpython / "Python.xcframework" / "Info.plist").is_file())
            self.assertTrue((cpython / "python" / "lib" / "python3.13" / "os.py").is_file())
            self.assertTrue((cpython / "python" / "lib" / "python3.13" / "_sysconfigdata__ios_arm64-iphoneos.py").is_file())
            self.assertFalse((cpython / "python" / "lib" / "python3.13" / "test" / "test_bad.py").exists())
            self.assertFalse((cpython / "python" / "lib" / "python3.13" / "tkinter" / "__init__.py").exists())
            self.assertTrue((cpython / "python" / "site-packages" / "requests" / "__init__.py").is_file())
            self.assertFalse((cpython / "python" / "site-packages" / "requests" / "__pycache__" / "ignored.pyc").exists())

            fwork_dev = cpython / "python" / "lib" / "python3.13" / "lib-dynload" / "_json.cpython-313-iphoneos.fwork"
            fwork_sim = cpython / "python" / "lib" / "python3.13" / "lib-dynload" / "_json.cpython-313-iphonesimulator.fwork"
            self.assertEqual(fwork_dev.read_text(encoding="utf-8").strip(), "Frameworks/PyExt__json.framework/PyExt__json")
            self.assertEqual(fwork_sim.read_text(encoding="utf-8").strip(), "Frameworks/PyExt__json.framework/PyExt__json")
            self.assertFalse((cpython / "python" / "lib" / "python3.13" / "lib-dynload" / "_testcapi.cpython-313-iphoneos.fwork").exists())

            plist_path = cpython / "ExtResources" / "iphoneos" / "Frameworks" / "PyExt__ssl.framework" / "Info.plist"
            plist_data = plistlib.loads(plist_path.read_bytes())
            self.assertEqual(plist_data["CFBundlePackageType"], "FMWK")
            self.assertEqual(plist_data["CFBundleExecutable"], "PyExt__ssl")
            self.assertEqual(plist_data["CFBundleIdentifier"], "io.ayugram.pyext.-ssl")
            self.assertEqual(plist_data["CFBundleSupportedPlatforms"], ["iPhoneOS"])

            origin = cpython / "ExtResources" / "iphoneos" / "Frameworks" / "PyExt__json.framework" / "PyExt__json.origin"
            self.assertEqual(origin.read_text(encoding="utf-8").strip(), "python/lib/python3.13/lib-dynload/_json.cpython-313-iphoneos.fwork")

            # Existing ExtResources BUILD file must not be removed during framework cleaning.
            self.assertTrue((cpython / "ExtResources" / "iphoneos" / "BUILD").is_file())

    def test_darwin_runs_install_name_tool(self):
        with tempfile.TemporaryDirectory() as tmp:
            fw_dir = Path(tmp)
            calls = []

            def fake_run(cmd, check=False):
                calls.append((cmd, check))

            with mock.patch.object(ayugram_python.subprocess, "run", side_effect=fake_run):
                ayugram_python._build_framework_bundle(
                    so_bytes=b"DATA",
                    module_name="_ssl",
                    platform_family="iPhoneOS",
                    frameworks_dir=fw_dir,
                    origin_fwork_relpath="python/lib/python3.13/lib-dynload/_ssl.cpython-313-iphoneos.fwork",
                    install_name_tool_path="/usr/bin/install_name_tool",
                )

            self.assertEqual(len(calls), 1)
            cmd, check = calls[0]
            self.assertTrue(check)
            self.assertEqual(cmd[0:3], ["/usr/bin/install_name_tool", "-id", "@rpath/PyExt__ssl.framework/PyExt__ssl"])

    def test_sha256_mismatch_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.tar.gz"
            bad.write_bytes(b"corrupt")
            with self.assertRaises(ValueError):
                ayugram_python._verify_sha256(bad, "0" * 64, "bad")

    def test_real_py313_tarball_if_present_in_scratch(self):
        scratch_tar = Path(
            r"C:\Users\Kek\.gemini\antigravity\brain\a4e0219e-279b-4547-8f5e-8df3992b6cfe\scratch\py313.tar.gz"
        )
        if not scratch_tar.is_file():
            self.skipTest("scratch py313.tar.gz not present")
        self.assertEqual(ayugram_python.sha256_file(scratch_tar), ayugram_python.PYTHON_APPLE_SUPPORT_SHA256)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            cache = Path(tmp) / "cache"
            cache.mkdir(parents=True)
            wheel = _make_synthetic_wheel(cache / "dummy-1.0-py3-none-any.whl", "dummy_mod", "OK = True\n")
            res = ayugram_python.prepare_python(
                source_root=root,
                python_archive=scratch_tar,
                cache_dir=cache,
                wheels=(wheel,),
                force=True,
            )
            self.assertEqual(len(res["kept_modules"]), 50)
            self.assertIn("_ssl", res["kept_modules"])
            self.assertIn("_json", res["kept_modules"])
            self.assertIn("_sqlite3", res["kept_modules"])
            self.assertNotIn("_testcapi", res["kept_modules"])


if __name__ == "__main__":
    unittest.main()
