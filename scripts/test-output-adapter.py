#!/usr/bin/env python3
"""Private test IPC namespace; never connects to the installed CoreMIDI driver."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
host = subprocess.Popen([str(root / 'work/driver-tests'), '--serve'], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    print(host.stdout.readline().strip())
    result = subprocess.run([str(root / 'work/build/debug/OutputSpyProbe')], cwd=root, capture_output=True, text=True, timeout=10)
    print(result.stdout, end='')
    print(result.stderr, end='')
    stdout, stderr = host.communicate(timeout=10)
    if result.returncode or host.returncode:
        raise SystemExit(f'FAIL: adapter={result.returncode}, host={host.returncode}\n{stdout}\n{stderr}')
finally:
    if host.poll() is None:
        host.terminate()
        host.wait(timeout=5)
