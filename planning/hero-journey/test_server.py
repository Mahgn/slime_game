"""Storage and HTTP contract tests. All files are isolated in a temporary directory."""

import copy
import hashlib
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from server import JourneyServer, MAX_BODY_BYTES, ValidationError, validate_project


def sample_project():
    node = {
        "id": "start", "chapterId": "c1", "x": 50, "y": 70,
        "title": "Дом", "kind": "story", "status": "draft", "location": "Луг",
        "goal": "Вернуться к стаду", "action": "Помочь другу", "change": "Начало пути",
        "emotion": "Тепло", "reveal": "", "requires": "", "notes": "",
        "sources": [{"label": "Концепт", "path": "docs/SOURCE_CONCEPT.md"}],
    }
    finish = dict(node, id="finish", x=500, kind="finale")
    return {
        "schemaVersion": 1, "id": "slime-journey", "title": "Путь героя", "subtitle": "Черновик",
        "chapters": [{"id": "c1", "title": "Начало", "subtitle": "Пролог", "color": "#48af83", "order": 0}],
        "nodes": [node, finish],
        "edges": [{"id": "e1", "from": "start", "to": "finish", "label": "Домой", "kind": "main"}],
    }


class ServerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix="hero-journey-tests-")
        cls.root = Path(cls.workspace.name) / "editor"
        cls.root.mkdir()
        (cls.root / "index.html").write_text("<!doctype html><title>Карта</title>", encoding="utf-8")
        (cls.root.parent / "secret.html").write_text("PRIVATE", encoding="utf-8")
        (cls.root / "server.py").write_text("PRIVATE", encoding="utf-8")
        cls.data_path = cls.root / "journey.json"
        cls.backup_dir = cls.root.parent / "backups"
        cls.server = JourneyServer(("127.0.0.1", 0), cls.root, cls.data_path, cls.backup_dir)
        cls.port = cls.server.server_port
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)
        cls.workspace.cleanup()

    def setUp(self):
        self.project = sample_project()
        self.raw = (json.dumps(self.project, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        self.data_path.write_bytes(self.raw)
        self.revision = hashlib.sha256(self.raw).hexdigest()

    def request(self, method="GET", path="/api/project", body=None, headers=None):
        request_headers = {}
        if body is not None:
            if isinstance(body, dict):
                body = json.dumps(body, ensure_ascii=False).encode("utf-8")
            request_headers.update({"Origin": f"http://127.0.0.1:{self.port}", "Content-Type": "application/json"})
        request_headers.update(headers or {})
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            connection.request(method, path, body=body, headers=request_headers)
            response = connection.getresponse()
            raw = response.read()
            content = json.loads(raw.decode("utf-8")) if "application/json" in response.getheader("Content-Type", "") else raw
            return response.status, content, dict(response.getheaders())
        finally:
            connection.close()

    def test_get_project_and_raw_revision(self):
        status, body, headers = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(body, {"project": self.project, "revision": self.revision})
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertNotIn("Access-Control-Allow-Origin", headers)

    def test_successful_save_is_persistent_and_has_exact_backup(self):
        before = set(self.backup_dir.glob("*.json"))
        self.project["nodes"][0]["title"] = "Новое начало"
        status, body, _ = self.request("PUT", body={"project": self.project, "revision": self.revision})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(self.data_path.read_bytes()), self.project)
        self.assertEqual(body["revision"], hashlib.sha256(self.data_path.read_bytes()).hexdigest())
        created = set(self.backup_dir.glob("*.json")) - before
        self.assertEqual(len(created), 1)
        self.assertEqual(created.pop().read_bytes(), self.raw)
        self.assertEqual(list(self.root.glob(".journey-*.tmp")), [])

    def test_stale_revision_cannot_overwrite_external_edit(self):
        external = copy.deepcopy(self.project)
        external["title"] = "Изменено помощником"
        new_raw = json.dumps(external, ensure_ascii=False).encode("utf-8")
        self.data_path.write_bytes(new_raw)
        status, body, _ = self.request("PUT", body={"project": self.project, "revision": self.revision})
        self.assertEqual(status, 409)
        self.assertEqual(body["project"], external)
        self.assertEqual(body["revision"], hashlib.sha256(new_raw).hexdigest())
        self.assertEqual(self.data_path.read_bytes(), new_raw)

    def test_concurrent_saves_accept_only_one_revision(self):
        responses = []
        barrier = threading.Barrier(2)

        def save(title):
            project = copy.deepcopy(self.project)
            project["title"] = title
            barrier.wait()
            responses.append(self.request("PUT", body={"project": project, "revision": self.revision})[0])

        threads = [threading.Thread(target=save, args=(title,)) for title in ("Первый", "Второй")]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=4)
        self.assertEqual(sorted(responses), [200, 409])

    def test_invalid_json_does_not_change_file(self):
        for body in (b"{", b'{"project":NaN}', b'{"a":1,"a":2}', b"\xff", b"[]"):
            with self.subTest(body=body):
                self.assertEqual(self.request("PUT", body=body)[0], 400)
                self.assertEqual(self.data_path.read_bytes(), self.raw)

    def test_invalid_schema_does_not_change_file(self):
        changes = [
            lambda project: project["nodes"][0].update(x=float("inf")),
            lambda project: project["nodes"][0].update(x=True),
            lambda project: project["nodes"][0].update(x=10 ** 400),
            lambda project: project["nodes"][0].update(chapterId="missing"),
            lambda project: project["nodes"][0].update(status="approved"),
            lambda project: project["nodes"][0].update(sources="bad"),
            lambda project: project["nodes"][0].update(extra="unsupported"),
            lambda project: project["nodes"][1].update(id="start"),
            lambda project: project["edges"][0].update(to="missing"),
            lambda project: project["edges"][0].update(to="start"),
            lambda project: project["chapters"][0].update(color="red"),
        ]
        for change in changes:
            project = copy.deepcopy(self.project)
            change(project)
            with self.subTest(project=project):
                self.assertEqual(self.request("PUT", body={"project": project, "revision": self.revision})[0], 400)
                self.assertEqual(self.data_path.read_bytes(), self.raw)

    def test_node_limit(self):
        project = copy.deepcopy(self.project)
        project["nodes"] = [dict(project["nodes"][0], id=f"n{index}") for index in range(501)]
        with self.assertRaises(ValidationError):
            validate_project(project)

    def test_external_invalid_file_is_not_replaced(self):
        self.data_path.write_bytes(b"broken")
        self.assertEqual(self.request()[0], 500)
        self.assertEqual(self.request("PUT", body={"project": self.project, "revision": self.revision})[0], 400)
        self.assertEqual(self.data_path.read_bytes(), b"broken")

    def test_path_traversal_and_private_files_are_not_served(self):
        for path in ("/../secret.html", "/%2e%2e/secret.html", "/%2e%2e%5csecret.html", "/journey.json",
                     "/server.py", "/.journey-a.tmp", "/foo/../../secret.html", "/C:/secret.html"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path=path)[0], 404)
        self.assertEqual(self.request(path="/")[0], 200)

    def test_host_and_origin_guard(self):
        self.assertEqual(self.request(headers={"Host": "attacker.invalid"})[0], 403)
        for origin in ("https://evil.invalid", "null", "", f"http://localhost:{self.port}"):
            with self.subTest(origin=origin):
                self.assertEqual(self.request("PUT", body={"project": self.project, "revision": self.revision},
                                              headers={"Origin": origin})[0], 403)
        self.assertEqual(self.data_path.read_bytes(), self.raw)

    def test_request_limits_and_content_type(self):
        self.assertEqual(self.request("PUT", body=b"{}", headers={"Content-Length": str(MAX_BODY_BYTES + 1)})[0], 413)
        self.assertEqual(self.request("PUT", body=b"{}", headers={"Content-Type": "text/plain"})[0], 415)
        self.assertEqual(self.data_path.read_bytes(), self.raw)

    def test_failed_replace_preserves_old_file(self):
        self.project["title"] = "Не должно сохраниться"
        with patch("server.os.replace", side_effect=OSError("simulated disk error")):
            self.assertEqual(self.request("PUT", body={"project": self.project, "revision": self.revision})[0], 500)
        self.assertEqual(self.data_path.read_bytes(), self.raw)
        self.assertEqual(list(self.root.glob(".journey-*.tmp")), [])

    def test_failed_backup_preserves_old_file(self):
        self.project["title"] = "Не должно сохраниться"
        old_dir = self.server.store.backup_dir
        self.server.store.backup_dir = self.root / "index.html"
        try:
            self.assertEqual(self.request("PUT", body={"project": self.project, "revision": self.revision})[0], 500)
        finally:
            self.server.store.backup_dir = old_dir
        self.assertEqual(self.data_path.read_bytes(), self.raw)

    def test_health_identifies_workspace(self):
        status, body, _ = self.request(path="/api/health")
        self.assertEqual(status, 200)
        self.assertEqual(body["service"], "slime-hero-journey")
        self.assertEqual(Path(body["projectPath"]), self.data_path.resolve())


if __name__ == "__main__":
    unittest.main(verbosity=2)
