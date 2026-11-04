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

from export_polygon import api_request, export, classify_failure, main


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

    def test_http_400_comment_is_classified_without_disclosing_credentials(self):
        payload = b'{"status":"FAILED","comment":"apiSig: Incorrect signature; fake-key fake-secret"}'
        error = urllib.error.HTTPError("https://example.invalid/?apiKey=fake-key", 400, "failure", {}, io.BytesIO(payload))
        with patch("export_polygon.urllib.request.urlopen", side_effect=error) as transport:
            with self.assertRaises(RuntimeError) as caught:
                api_request("problem.packages", {}, "fake-key", "fake-secret")
        self.assertEqual(transport.call_count, 1)
        self.assertEqual(caught.exception.record["reason_code"], "AUTH_SIGNATURE")
        self.assertEqual(caught.exception.record["response_sample_sha256"], hashlib.sha256(payload).hexdigest())
        diagnostic = str(caught.exception) + json.dumps(caught.exception.record)
        self.assertNotIn("fake-key", diagnostic)
        self.assertNotIn("fake-secret", diagnostic)

    def test_nonjson_error_has_no_raw_body_in_diagnostic(self):
        error = urllib.error.HTTPError("https://example.invalid", 400, "failure", {}, io.BytesIO(b'<html>fake-secret</html>'))
        with patch("export_polygon.urllib.request.urlopen", side_effect=error):
            with self.assertRaises(RuntimeError) as caught:
                api_request("problem.packages", {}, "fake-key", "fake-secret")
        self.assertEqual(caught.exception.record["reason_code"], "NON_JSON_OR_TRUNCATED_RESPONSE")
        self.assertNotIn("fake-secret", str(caught.exception))

    def test_failure_categories(self):
        for text, code in [
            ("apiKey: Incorrect API key", "AUTH_KEY"),
            ("time: Time is out of range", "AUTH_TIME"),
            ("Pin is incorrect", "PIN_REQUIRED_OR_INVALID"),
            ("Too many attempts", "RATE_LIMIT"),
            ("problemId: Problem not found", "ACCESS_OR_NOT_FOUND"),
            ("Unknown method", "REQUEST_FORMAT"),
            ("Unexpected response", "UNCLASSIFIED"),
        ]:
            with self.subTest(text=text):
                self.assertEqual(classify_failure(text), code)

    def test_main_saves_sanitized_failure_and_preserves_prior_results(self):
        out = self.output()
        responses = [io.BytesIO(b'{"status":"OK","result":[]}'),
            urllib.error.HTTPError("https://example.invalid", 400, "failure", {}, io.BytesIO(b'{"comment":"apiKey: fake-key fake-secret"}'))]
        with patch("sys.argv", ["export_polygon.py", "--problem-id", "123", "--out", str(out)]), patch("export_polygon.getpass.getpass", side_effect=["fake-key", "fake-secret"]), patch("export_polygon.urllib.request.urlopen", side_effect=responses) as transport, patch("sys.stdout", new_callable=io.StringIO) as console:
            self.assertEqual(main(), 2)
        self.assertEqual(transport.call_count, 2)
        self.assertTrue((out / "packages.json").exists())
        record = json.loads((out / "failure.json").read_text())
        self.assertEqual(record["method"], "problem.invocations")
        self.assertEqual(record["reason_code"], "AUTH_KEY")
        self.assertFalse(record["retried"])
        self.assertNotIn("fake-key", console.getvalue() + json.dumps(record))
        self.assertNotIn("fake-secret", console.getvalue() + json.dumps(record))

    def test_whitespace_credentials_stop_before_network(self):
        with patch("sys.argv", ["export_polygon.py", "--problem-id", "123", "--out", str(self.output())]), patch("export_polygon.getpass.getpass", side_effect=[" fake-key", "fake-secret"]), patch("export_polygon.urllib.request.urlopen") as transport, patch("sys.stderr", new_callable=io.StringIO):
            with self.assertRaises(SystemExit):
                main()
        transport.assert_not_called()

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
