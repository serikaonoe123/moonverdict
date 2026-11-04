"""User-run read-only Polygon export. Credentials are prompted locally, never saved.

Without --invocation-id this lists available stored invocations. Run again with
a new output directory and the chosen ID to capture its result and package info.
"""
import argparse
import getpass
import hashlib
import json
from pathlib import Path
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

READ_METHODS = {"problem.packages", "problem.invocations", "problem.invocation"}


def api_request(method, parameters, key, secret):
    if method not in READ_METHODS:
        raise ValueError("Only whitelisted read operations are supported")
    params = {**parameters, "apiKey": key, "time": str(int(time.time()))}
    query = urllib.parse.urlencode(sorted(params.items()))
    nonce = secrets.token_hex(3)
    signature = hashlib.sha512(f"{nonce}/{method}?{query}#{secret}".encode()).hexdigest()
    body = (query + "&apiSig=" + nonce + signature).encode()
    request = urllib.request.Request("https://polygon.codeforces.com/api/" + method, data=body)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            envelope = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Polygon HTTP status {error.code}; stopped without retry") from None
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError("Polygon connection failed; stopped without retry") from None
    if envelope.get("status") != "OK":
        raise RuntimeError("Polygon API refused or failed the request; stopped without retry")
    return envelope


def export(problem_id, invocation_id, destination, key, secret, request=api_request):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    def save(name, value):
        (destination / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    parameters = {"problemId": str(problem_id)}
    packages = request("problem.packages", parameters, key, secret)
    save("packages.json", packages)
    invocations = request("problem.invocations", parameters, key, secret)
    save("invocations.json", invocations)
    if invocation_id is not None:
        invocation = request("problem.invocation", {**parameters, "invocationId": str(invocation_id)}, key, secret)
        save("invocation.json", invocation)
        data = invocation["result"]["invocation"]
        if data["id"] != invocation_id:
            raise ValueError("Returned invocation ID differs")
        package_id = data.get("packageId")
        matches = [p for p in packages["result"] if p["id"] == package_id]
        if len(matches) != 1:
            raise ValueError("No unique package binding; saved records retained")
        save("selected-package.json", matches[0])
    save("capture.json", {"problem_id": problem_id, "invocation_id": invocation_id,
        "captured_at_unix": int(time.time()), "evidence_level": "api-capture-not-run-binding-proof"})
    return invocations["result"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--problem-id", required=True, type=int)
    parser.add_argument("--invocation-id", type=int)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    if args.problem_id <= 0 or (args.invocation_id is not None and args.invocation_id <= 0):
        parser.error("IDs must be positive")
    if args.out.exists():
        parser.error("Output already exists; choose a new directory")
    key = getpass.getpass("Polygon API key (local only): ")
    secret = getpass.getpass("Polygon API secret (local only): ")
    if not key or not secret:
        parser.error("Empty credentials")
    try:
        invocations = export(args.problem_id, args.invocation_id, args.out, key, secret)
    except (RuntimeError, ValueError, OSError, KeyError, TypeError) as error:
        print(f"Export stopped: {error}. Keep any files already saved. No retry or permission changes performed.")
        return 2
    for item in invocations:
        print("invocation", item.get("id"), "package", item.get("packageId"), "testset", item.get("testset"), "status", item.get("status"))
    print("Saved local records to", args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
