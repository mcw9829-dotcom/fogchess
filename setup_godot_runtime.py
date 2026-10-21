"""Install an isolated official stable runtime; never alter Steam or system settings."""
import hashlib
import urllib.request
import zipfile
from godot_runtime import LOCAL_EXE


def main():
    target = LOCAL_EXE.parent
    target.mkdir(parents=True, exist_ok=True)
    name = "Godot_v4.7.1-stable_win64.exe.zip"
    base = "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/"
    checksums = urllib.request.urlopen(base + "SHA512-SUMS.txt", timeout=60).read().decode()
    expected = next(line.split()[0] for line in checksums.splitlines()
                    if line.split()[-1].lstrip("*") == name)
    archive = target / name
    if not archive.is_file() or hashlib.sha512(archive.read_bytes()).hexdigest() != expected:
        with urllib.request.urlopen(base + name, timeout=60) as response:
            archive.write_bytes(response.read())
    if hashlib.sha512(archive.read_bytes()).hexdigest() != expected:
        raise SystemExit("Godot download checksum mismatch; extraction cancelled.")
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            if not (target / member.filename).resolve().is_relative_to(target.resolve()):
                raise SystemExit("Unsafe archive path; extraction cancelled.")
        package.extractall(target)
    print(f"Verified official Godot 4.7.1: {LOCAL_EXE}")


if __name__ == "__main__":
    main()
