"""Run the same checks on Windows and Linux, retaining command diagnostics."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results"
OUT.mkdir(exist_ok=True)
commands = [
    ["moon", "version", "--all"],
    ["moon", "fmt", "--check"],
    ["moon", "check", "--target", "js", "--deny-warn"],
    *[["moon", "test", "--target", target, "--deny-warn"] for target in ["js", "native", "wasm-gc"]],
    ["moon", "build", "--target", "js"],
    ["moon", "info"],
    ["git", "diff", "--exit-code", "--", "pkg.generated.mbti", "cmd/moonverdict/pkg.generated.mbti"],
    ["python", "scripts/check_cli.py"],
    ["python", "scripts/test_export_polygon.py"],
]
records = []
for index, command in enumerate(commands):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = result.stdout + result.stderr
    (OUT / f"check-{index:02}.log").write_text(output, encoding="utf-8")
    print(" ".join(command), result.returncode, flush=True)
    if index == 0 and result.returncode == 0 and "v0.10.17+d971670cd" not in output:
        raise SystemExit("Toolchain differs from the tested pin")
    records.append({"command": command, "exit_code": result.returncode})
    (OUT / "checks.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
    if result.returncode:
        print(output)
        raise SystemExit(result.returncode)
