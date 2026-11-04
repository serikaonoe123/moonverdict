"""Black-box CLI contract checks. Run after `moon build --target js`."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/js/debug/build/cmd/moonverdict/moonverdict.js"
BEFORE = ROOT / "examples/before.json"
AFTER = ROOT / "examples/after.json"


def run(*args):
    return subprocess.run(["node", str(CLI), *map(str, args)], capture_output=True, text=True, encoding="utf-8")


def check(condition, message):
    if not condition:
        raise AssertionError(message)


unchanged = run(BEFORE, BEFORE)
check(unchanged.returncode == 0 and not json.loads(unchanged.stdout)["findings"], "unchanged")
changed = run(BEFORE, AFTER)
check(changed.returncode == 1, "review exit code")
check(json.loads(changed.stdout)["findings"][0]["code"] == "KNOWN_FAILURE_LOST", "lost witness")
html = run(BEFORE, AFTER, "html")
check(html.returncode == 1 and html.stdout.startswith("<!doctype html>"), "HTML")
check(run().returncode == 2, "usage")
check(run(BEFORE, ROOT / "no-such-file.json").returncode == 2, "missing file")
check(run(BEFORE, AFTER, "typo").returncode == 2, "invalid format")
with tempfile.TemporaryDirectory(prefix="moonverdict-cli-") as temp:
    invalid = Path(temp) / "invalid.json"
    invalid.write_text("{", encoding="utf-8")
    check(run(BEFORE, invalid).returncode == 2, "malformed input")
    value = json.loads(AFTER.read_text(encoding="utf-8"))
    value["runs"] = []
    invalid.write_text(json.dumps(value), encoding="utf-8")
    incomplete = run(BEFORE, invalid)
    codes = [f["code"] for f in json.loads(incomplete.stdout)["findings"]]
    check(incomplete.returncode == 1 and "INCOMPLETE" in codes and "KNOWN_FAILURE_LOST" not in codes, "missing results")

results = ROOT / "results"
results.mkdir(exist_ok=True)
(results / "example-report.html").write_text(html.stdout, encoding="utf-8")
(results / "example-report.json").write_text(changed.stdout, encoding="utf-8")
print("CLI: 8 checks passed; example reports written to results/.")
