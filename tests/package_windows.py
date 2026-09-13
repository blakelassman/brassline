"""Build a portable ZIP only when the pinned Windows engine is complete."""
from pathlib import Path
import hashlib
import struct
import sys
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
ENGINE_HASHES = {
    "Godot_v4.7.2-stable_win64.exe": "ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424",
    "Godot_v4.7.2-stable_win64_console.exe": "c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643",
}


def validate_engine(name, data):
    if hashlib.sha256(data).hexdigest() != ENGINE_HASHES[name]:
        raise ValueError(f"Incomplete or changed engine: {name}")
    pe = struct.unpack_from("<I", data, 60)[0]
    assert data[:2] == b"MZ" and data[pe:pe + 4] == b"PE\0\0"
    assert struct.unpack_from("<H", data, pe + 4)[0] == 0x8664
    count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    for i in range(count):
        section = pe + 24 + optional_size + i * 40
        size, offset = struct.unpack_from("<II", data, section + 16)
        if offset + size > len(data):
            raise ValueError(f"Truncated executable section: {name}")


def main():
    destination = Path(sys.argv[1]).resolve()
    for name in ENGINE_HASHES:
        validate_engine(name, (ROOT / "engine" / name).read_bytes())
    with ZipFile(destination, "w", ZIP_DEFLATED, compresslevel=6) as archive:
        for source in sorted(ROOT.rglob("*")):
            relative = source.relative_to(ROOT)
            if (not source.is_file() or any(part in {".git", ".godot"} for part in relative.parts)
                    or "__pycache__" in relative.parts
                    or source.suffix in {".import", ".log", ".pyc", ".zip"}):
                continue
            archive.write(source, Path("Brassline_Prototype_0_9_0") / relative)
    with ZipFile(destination) as archive:
        assert archive.testzip() is None
        for name in ENGINE_HASHES:
            data = archive.read(f"Brassline_Prototype_0_9_0/engine/{name}")
            validate_engine(name, data)
            assert data == (ROOT / "engine" / name).read_bytes()
            print(f"PASS Packaged {name}: {len(data)} bytes, pinned SHA-256 verified")
    print(f"PASS ZIP integrity: {destination.name} ({destination.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
