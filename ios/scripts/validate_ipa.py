"""Validate the unsigned device package; does not validate a third-party signature."""
import json
import plistlib
import struct
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as package:
    names = package.namelist()
    assert package.testzip() is None, "Corrupt ZIP"
    apps = [p for p in names if p.count("/") == 2 and p.endswith(".app/")]
    assert len(apps) == 1 and apps[0].startswith("Payload/"), "Expected one app under Payload"
    assert not any("Payload/Payload" in p for p in names), "Nested Payload"
    root = apps[0]
    info = plistlib.loads(package.read(root + "Info.plist"))
    for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleVersion", "CFBundleShortVersionString"):
        assert isinstance(info.get(key), str) and info[key], key
        assert "$(" not in info[key], "Unexpanded setting: " + key
    assert info["CFBundlePackageType"] == "APPL"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    executable = package.read(root + info["CFBundleExecutable"])
    magic, cpu, _, kind = struct.unpack_from("<IIII", executable)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and kind == 2, "Expected arm64 Mach-O executable"
    assert package.getinfo(root + info["CFBundleExecutable"]).external_attr >> 16 & 0o111, "Missing executable permission"
    assert root + "Assets.car" in names, "Missing compiled assets"
    assert info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon"), "Missing app icon metadata"
    print(json.dumps({"result": "PASS", "signature": "unsigned; installation requires signing", "metadata": info}, indent=2))
