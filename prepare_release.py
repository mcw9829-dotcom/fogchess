"""Build and validate local deployable assets. Never deploy or access the DB."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
WEB = ROOT / 'godot' / 'build' / 'web'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=os.environ.get('GODOT_EXE', r'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'))
    parser.add_argument('--skip-export', action='store_true', help='Validate an already exported build')
    args = parser.parse_args()
    if not args.skip_export:
        result = subprocess.run([args.godot, '--headless', '--path', str(ROOT / 'godot'),
                                 '--export-release', 'Web'], cwd=ROOT, capture_output=True, timeout=180)
        output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
        (ROOT / 'godot' / 'release-export.log').write_text(output, encoding='utf-8')
        if result.returncode or 'ERROR:' in output or 'SCRIPT ERROR' in output:
            raise SystemExit('Export failed. See godot/release-export.log')
    for extension in ('html', 'js', 'wasm', 'pck'):
        file = WEB / f'index.{extension}'
        if not file.is_file() or not file.stat().st_size:
            raise SystemExit(f'Missing export: {file.name}')
    manifest = {}
    for file in sorted(WEB.iterdir()):
        if file.suffix not in ('.html', '.js', '.wasm', '.pck', '.png', '.svg', '.ico'):
            continue
        content = file.read_bytes()
        if file.suffix in ('.js', '.wasm', '.pck'):
            file.with_name(file.name + '.gz').write_bytes(gzip.compress(content, compresslevel=6, mtime=0))
        manifest[file.name] = {'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()}
    (WEB.parent / 'release-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(f'Ready: {len(manifest)} assets; {sum(f.stat().st_size for f in WEB.glob("*.gz")) / 1048576:.1f} MiB compressed JS/WASM/PCK.')
    print('No deployment performed. Run python test_web_host.py before reviewing deployment.')


if __name__ == '__main__':
    main()
