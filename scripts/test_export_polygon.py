"""Offline exporter tests: fake transport and fake credentials only."""
import hashlib
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error
import urllib.parse
import uuid

from export_polygon import api_request, export


class ExportTests(unittest.TestCase):
    def output(self):
        return Path(__file__).resolve().parents[1] / "results" / ("export-test-" + uuid.uuid4().hex)

    def test_signed_read_request(self):
        with patch("export_polygon.time.time", return_value=1000), patch("export_polygon.secrets.token_hex", return_value="abcdef"), patch("export_polygon.urllib.request.urlopen", return_value=io.BytesIO(b'{"status":"OK","result":[]}')) as transport:
            api_request("problem.packages", {"problemId": "123"}, "fake-key", "fake-secret")
        request = transport.call_args.args[0]
        self.assertEqual(request.full_url, "https://polygon.codeforces.com/api/problem.packages")
        body = urllib.parse.parse_qs(request.data.decode())
        expected = hashlib.sha512(b"abcdef/problem.packages?apiKey=fake-key&problemId=123&time=1000#fake-secret").hexdigest()
        self.assertEqual(body["apiSig"], ["abcdef" + expected])
        self.assertNotIn(b"fake-secret", request.data)

    def test_nonread_operation_never_reaches_transport(self):
        with patch("export_polygon.urllib.request.urlopen") as transport:
            with self.assertRaises(ValueError):
                api_request("problem.buildPackage", {}, "fake-key", "fake-secret")
            transport.assert_not_called()

    def test_refusal_is_not_retried(self):
        with patch("export_polygon.urllib.request.urlopen", return_value=io.BytesIO(b'{"status":"FAILED","comment":"fake-secret"}')) as transport:
            with self.assertRaises(RuntimeError) as caught:
                api_request("problem.packages", {}, "fake-key", "fake-secret")
            self.assertEqual(transport.call_count, 1)
            self.assertNotIn("fake-secret", str(caught.exception))

    def test_http_failure_does_not_leak_request_or_retry(self):
        error = urllib.error.HTTPError("https://example.invalid/?apiKey=fake-key", 403, "fake-secret", {}, None)
        with patch("export_polygon.urllib.request.urlopen", side_effect=error) as transport:
            with self.assertRaises(RuntimeError) as caught:
                api_request("problem.packages", {}, "fake-key", "fake-secret")
            self.assertEqual(transport.call_count, 1)
            self.assertNotIn("fake-key", str(caught.exception))
            self.assertNotIn("fake-secret", str(caught.exception))

        error.close()

    def test_export_retains_source_without_credentials(self):
        out = self.output()
        calls = []
        def fake(method, parameters, key, secret):
            calls.append(method)
            result = {"problem.packages": [{"id": 10, "revision": 2}],
                "problem.invocations": [{"id": 20, "packageId": 10}],
                "problem.invocation": {"invocation": {"id": 20, "packageId": 10}}}[method]
            return {"status": "OK", "result": result}
        export(123, 20, out, "fake-key", "fake-secret", request=fake)
        self.assertEqual(len(calls), 3)
        self.assertEqual(json.loads((out / "selected-package.json").read_text())["revision"], 2)
        self.assertTrue((out / "invocation.json").exists())
        for file in out.iterdir():
            self.assertNotIn("fake-key", file.read_text())
            self.assertNotIn("fake-secret", file.read_text())
        with self.assertRaises(FileExistsError):
            export(123, 20, out, "fake-key", "fake-secret", request=fake)


if __name__ == "__main__":
    unittest.main()
