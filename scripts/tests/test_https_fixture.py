"""Контракт барьеров на настоящем loopback-сервере без запуска Simulator."""

import base64
from concurrent.futures import ThreadPoolExecutor
import http.client
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("https_fixture", Path(__file__).resolve().parents[1] / "https-fixture.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BarrierTests(unittest.TestCase):
    payload = b"synthetic-barrier-payload"

    def fixture(self, timeout=5):
        temporary = tempfile.TemporaryDirectory(prefix="crafttalk-barrier-test-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        resources = root / "resources"
        resources.mkdir()
        fixture = module.Fixture(root, resources, root / "requests.jsonl",
                                 hold_timeout=timeout, body_timeout=timeout)
        self.addCleanup(fixture.close)
        return fixture

    def control(self, fixture, command):
        connection = http.client.HTTPConnection("127.0.0.1", fixture.ports["http"], timeout=3)
        try:
            connection.request("POST", "/control/barriers", body=json.dumps(command))
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            return json.loads(response.read())
        finally:
            connection.close()

    def configure(self, fixture):
        self.control(fixture, {"routes": {
            phase: {phase: True, "body": base64.b64encode(self.payload).decode()}
            for phase in ("hold", "holdAfterHeaders")
        }})

    def download(self, fixture, phase):
        connection = http.client.HTTPConnection("127.0.0.1", fixture.ports["http"], timeout=8)
        try:
            connection.request("GET", "/case/barriers/" + phase)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def wait_for_requests(self, fixture):
        with fixture.condition:
            self.assertTrue(fixture.condition.wait_for(
                lambda: len(fixture.cases["barriers"]["requests"]) == 2, timeout=3))

    def assert_interrupted(self, downloads):
        # До заголовков нет HTTP-ответа, после заголовков тело остаётся неполным.
        for phase, error in (("hold", http.client.RemoteDisconnected),
                             ("holdAfterHeaders", http.client.IncompleteRead)):
            with self.subTest(phase=phase), self.assertRaises(error):
                downloads[phase].result(timeout=8)

    def start_downloads(self, pool, fixture):
        return {phase: pool.submit(self.download, fixture, phase)
                for phase in ("hold", "holdAfterHeaders")}

    def test_explicit_release_completes_both_responses_without_errors(self):
        fixture = self.fixture()
        self.configure(fixture)
        with ThreadPoolExecutor(max_workers=2) as pool:
            downloads = self.start_downloads(pool, fixture)
            self.wait_for_requests(fixture)
            for phase in downloads:
                self.control(fixture, {"release": phase})
            for response in downloads.values():
                self.assertEqual(response.result(timeout=3), (200, self.payload))
        self.assertEqual(fixture.errors, [])
        self.assertEqual(json.loads(fixture.error_path.read_text()), [])

    def test_timeout_interrupts_responses_and_survives_reset(self):
        fixture = self.fixture(timeout=0.2)
        self.configure(fixture)
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assert_interrupted(self.start_downloads(pool, fixture))
        expected = [{"case": "barriers", "route": phase, "phase": phase,
                     "error": "release-timeout", "timeoutSeconds": 0.2}
                    for phase in ("hold", "holdAfterHeaders")]
        self.assertCountEqual(fixture.errors, expected)
        self.assertCountEqual(json.loads(fixture.error_path.read_text()), expected)
        self.control(fixture, {"reset": True})
        self.control(fixture, {"release": "hold"})
        fixture.close()
        self.assertCountEqual(fixture.errors, expected)
        self.assertCountEqual(json.loads(fixture.error_path.read_text()), expected)

    def test_reset_cancels_responses_without_timeout_errors(self):
        fixture = self.fixture()
        self.configure(fixture)
        with ThreadPoolExecutor(max_workers=2) as pool:
            downloads = self.start_downloads(pool, fixture)
            self.wait_for_requests(fixture)
            self.control(fixture, {"reset": True})
            self.assert_interrupted(downloads)
        self.assertEqual(fixture.errors, [])

    def test_shutdown_cancels_responses_without_timeout_errors(self):
        fixture = self.fixture()
        self.configure(fixture)
        with ThreadPoolExecutor(max_workers=2) as pool:
            downloads = self.start_downloads(pool, fixture)
            self.wait_for_requests(fixture)
            fixture.close()
            self.assert_interrupted(downloads)
        self.assertEqual(fixture.errors, [])


if __name__ == "__main__":
    unittest.main()
