"""Local, dependency-free editor storage for the Slime hero journey.

Run from any directory: python server.py [--port 8766].
The UI and this server share journey.json; no game files are written.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit


MAX_BODY_BYTES = 2 * 1024 * 1024
MAX_NODES = 500
MAX_EDGES = 2000
ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$")
STATIC_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".woff2": "font/woff2",
}


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def exact_keys(value, keys, context):
    require(isinstance(value, dict), f"{context}: требуется объект.")
    require(set(value) == set(keys), f"{context}: неверный набор полей.")


def string(value, context, limit=6000):
    require(isinstance(value, str), f"{context}: требуется строка.")
    require(len(value) <= limit, f"{context}: не более {limit} символов.")


def identifier(value, context):
    string(value, context, 80)
    require(ID_PATTERN.fullmatch(value) is not None, f"{context}: неверный ID.")


def number(value, context, minimum=-100000, maximum=100000):
    require(type(value) in (int, float),
            f"{context}: требуется конечное число.")
    require(minimum <= value <= maximum, f"{context}: число вне допустимого диапазона.")
    require(math.isfinite(value), f"{context}: требуется конечное число.")


def validate_project(project):
    exact_keys(project, ("schemaVersion", "id", "title", "subtitle", "chapters", "nodes", "edges"), "Карта")
    require(type(project["schemaVersion"]) is int and project["schemaVersion"] == 1,
            "Поддерживается schemaVersion: 1.")
    identifier(project["id"], "Карта.id")
    string(project["title"], "Название карты", 300)
    string(project["subtitle"], "Описание карты", 6000)
    chapters, nodes, edges = project["chapters"], project["nodes"], project["edges"]
    require(isinstance(chapters, list) and 1 <= len(chapters) <= 30, "Нужно от 1 до 30 глав.")
    require(isinstance(nodes, list) and len(nodes) <= MAX_NODES, f"Не более {MAX_NODES} этапов.")
    require(isinstance(edges, list) and len(edges) <= MAX_EDGES, f"Не более {MAX_EDGES} связей.")
    chapter_ids = set()
    for chapter in chapters:
        exact_keys(chapter, ("id", "title", "subtitle", "color", "order"), "Глава")
        identifier(chapter["id"], "Глава.id")
        require(chapter["id"] not in chapter_ids, "ID глав должны быть уникальны.")
        chapter_ids.add(chapter["id"])
        string(chapter["title"], "Название главы", 300)
        string(chapter["subtitle"], "Описание главы", 3000)
        string(chapter["color"], "Цвет главы", 7)
        require(re.fullmatch(r"#[0-9a-fA-F]{6}", chapter["color"]) is not None,
                "Цвет главы должен иметь вид #12ab34.")
        number(chapter["order"], "Порядок главы", 0, 10000)
    node_ids = set()
    for node in nodes:
        exact_keys(node, ("id", "chapterId", "x", "y", "title", "kind", "status", "location",
                          "goal", "action", "change", "emotion", "reveal", "requires", "notes", "sources"), "Этап")
        identifier(node["id"], "Этап.id")
        require(node["id"] not in node_ids, "ID этапов должны быть уникальны.")
        node_ids.add(node["id"])
        require(isinstance(node["chapterId"], str) and node["chapterId"] in chapter_ids,
                "Этап ссылается на неизвестную главу.")
        number(node["x"], "Этап.x")
        number(node["y"], "Этап.y")
        string(node["title"], "Название этапа", 300)
        require(isinstance(node["kind"], str) and node["kind"] in
                {"story", "combat", "discovery", "choice", "rest", "finale"}, "Неизвестный тип этапа.")
        require(isinstance(node["status"], str) and node["status"] in
                {"draft", "question", "prototype", "canon"}, "Неизвестный статус этапа.")
        for field in ("location", "goal", "action", "change", "emotion", "reveal", "requires", "notes"):
            string(node[field], f"Этап.{field}")
        require(isinstance(node["sources"], list) and len(node["sources"]) <= 30, "Не более 30 источников этапа.")
        for source in node["sources"]:
            exact_keys(source, ("label", "path"), "Источник")
            string(source["label"], "Название источника", 300)
            string(source["path"], "Путь источника", 1000)
    edge_ids = set()
    for edge in edges:
        exact_keys(edge, ("id", "from", "to", "label", "kind"), "Связь")
        identifier(edge["id"], "Связь.id")
        require(edge["id"] not in edge_ids, "ID связей должны быть уникальны.")
        edge_ids.add(edge["id"])
        require(isinstance(edge["from"], str) and isinstance(edge["to"], str)
                and edge["from"] in node_ids and edge["to"] in node_ids,
                "Связь должна соединять существующие этапы.")
        require(edge["from"] != edge["to"], "Этап нельзя соединить с самим собой.")
        string(edge["label"], "Подпись связи", 1000)
        require(isinstance(edge["kind"], str) and edge["kind"] in {"main", "branch", "return"},
                "Неизвестный тип связи.")
    return project


def reject_constant(value):
    raise ValidationError(f"Недопустимое значение JSON: {value}.")


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, f"Повтор поля JSON: {key}.")
        value[key] = item
    return value


def decode_json(raw):
    try:
        return json.loads(raw.decode("utf-8-sig"), parse_constant=reject_constant,
                          object_pairs_hook=unique_object)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ValidationError("Некорректный JSON в UTF-8.") from error


def revision_of(raw):
    return hashlib.sha256(raw).hexdigest()


class ProjectStore:
    def __init__(self, project_path, backup_dir):
        self.project_path = Path(project_path)
        self.backup_dir = Path(backup_dir)
        self.lock = threading.Lock()

    def read(self):
        raw = self.project_path.read_bytes()
        require(len(raw) <= MAX_BODY_BYTES, "Файл карты превышает 2 MiB.")
        project = validate_project(decode_json(raw))
        return project, revision_of(raw), raw

    def save(self, project, revision):
        validate_project(project)
        encoded = (json.dumps(project, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
        require(len(encoded) <= MAX_BODY_BYTES, "Файл карты превышает 2 MiB.")
        with self.lock:
            current, current_revision, previous_raw = self.read()
            if revision != current_revision:
                return False, current, current_revision
            if encoded == previous_raw:
                return True, current, current_revision
            self.backup_dir.mkdir(parents=True, exist_ok=True)
            backup = self.backup_dir / f"{time.time_ns()}-{current_revision[:12]}.json"
            with backup.open("xb") as stream:
                stream.write(previous_raw)
                stream.flush()
                os.fsync(stream.fileno())
            temp_path = None
            try:
                with tempfile.NamedTemporaryFile(mode="wb", prefix=".journey-", suffix=".tmp",
                                                 dir=self.project_path.parent, delete=False) as stream:
                    temp_path = Path(stream.name)
                    stream.write(encoded)
                    stream.flush()
                    os.fsync(stream.fileno())
                # Also detect edits made by another process while preparing the write.
                latest, latest_revision, _ = self.read()
                if latest_revision != current_revision:
                    return False, latest, latest_revision
                os.replace(temp_path, self.project_path)
                return True, project, revision_of(encoded)
            finally:
                if temp_path is not None and temp_path.exists():
                    temp_path.unlink()


class JourneyServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, static_root, project_path, backup_dir):
        self.static_root = Path(static_root).resolve()
        self.store = ProjectStore(project_path, backup_dir)
        super().__init__(address, JourneyHandler)


class JourneyHandler(BaseHTTPRequestHandler):
    server_version = "HeroJourney/1"

    def send_bytes(self, status, body, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json_response(self, status, payload):
        self.send_bytes(status, json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8"),
                        "application/json; charset=utf-8")

    def guard(self, write=False):
        port = self.server.server_port
        allowed = {f"127.0.0.1:{port}", f"localhost:{port}"}
        hosts = self.headers.get_all("Host") or []
        if len(hosts) != 1 or hosts[0] not in allowed:
            self.json_response(403, {"error": "Доступ разрешён только через локальный адрес редактора."})
            return False
        origins = self.headers.get_all("Origin") or []
        if write and (len(origins) != 1 or origins[0] != f"http://{hosts[0]}"):
            self.json_response(403, {"error": "Сохранение разрешено только из локального редактора."})
            return False
        return True

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if not self.guard():
            return
        path = urlsplit(self.path).path
        if path == "/api/health":
            self.json_response(200, {"service": "slime-hero-journey", "schemaVersion": 1,
                                     "projectPath": str(self.server.store.project_path.resolve())})
            return
        if path == "/api/project":
            try:
                with self.server.store.lock:
                    project, revision, _ = self.server.store.read()
                self.json_response(200, {"project": project, "revision": revision})
            except (OSError, ValidationError) as error:
                self.log_error("Cannot read project: %s", error)
                self.json_response(500, {"error": "Не удалось прочитать journey.json. Проверьте файл и журнал сервера."})
            return
        path = unquote(path)
        if path == "/":
            path = "/index.html"
        parts = path.lstrip("/").split("/")
        if "\\" in path or "\x00" in path or any(part.startswith(".") or ":" in part for part in parts):
            self.json_response(404, {"error": "Файл не найден."})
            return
        target = (self.server.static_root / path.lstrip("/")).resolve()
        if not target.is_relative_to(self.server.static_root) or target.suffix.lower() not in STATIC_TYPES:
            self.json_response(404, {"error": "Файл не найден."})
            return
        try:
            body = target.read_bytes()
        except OSError:
            self.json_response(404, {"error": "Файл не найден."})
            return
        self.send_bytes(200, body, STATIC_TYPES[target.suffix.lower()])

    def do_PUT(self):
        if not self.guard(write=True):
            return
        if urlsplit(self.path).path != "/api/project":
            self.json_response(404, {"error": "Неизвестный адрес сохранения."})
            return
        lengths = self.headers.get_all("Content-Length") or []
        if self.headers.get("Transfer-Encoding") or len(lengths) != 1:
            self.json_response(411, {"error": "Требуется один заголовок Content-Length."})
            return
        try:
            size = int(lengths[0])
        except ValueError:
            self.json_response(400, {"error": "Некорректный размер запроса."})
            return
        if not 0 < size <= MAX_BODY_BYTES:
            self.json_response(413, {"error": "Запрос должен занимать не более 2 MiB."})
            return
        if self.headers.get_content_type() != "application/json":
            self.json_response(415, {"error": "Требуется Content-Type: application/json."})
            return
        try:
            self.connection.settimeout(10)
            raw = self.rfile.read(size)
            require(len(raw) == size, "Запрос получен не полностью.")
            envelope = decode_json(raw)
            exact_keys(envelope, ("project", "revision"), "Запрос сохранения")
            string(envelope["revision"], "Ревизия", 64)
            require(re.fullmatch(r"[0-9a-f]{64}", envelope["revision"]) is not None, "Неверная ревизия файла.")
            saved, project, revision = self.server.store.save(envelope["project"], envelope["revision"])
            payload = {"project": project, "revision": revision}
            if not saved:
                payload["error"] = "Файл уже изменён. Загрузите новую версию, сохранив свои правки отдельно."
            self.json_response(200 if saved else 409, payload)
        except ValidationError as error:
            self.json_response(400, {"error": str(error)})
        except (OSError, ValueError) as error:
            self.log_error("Cannot save project: %s", error)
            self.json_response(500, {"error": "Карта не сохранена. Проверьте файл и журнал сервера."})


def main():
    parser = argparse.ArgumentParser(description="Локальная изменяемая карта пути героя")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Порт должен быть в диапазоне 1–65535.")
    root = Path(__file__).resolve().parent
    store_path = root / "journey.json"
    backup_dir = root.parent.parent / "output" / "hero_journey" / "backups"
    try:
        ProjectStore(store_path, backup_dir).read()
        server = JourneyServer(("127.0.0.1", args.port), root, store_path, backup_dir)
    except (OSError, ValidationError) as error:
        parser.exit(1, f"Не удалось запустить редактор: {error}\n")
    print(f"Карта пути героя: http://127.0.0.1:{server.server_port}/", flush=True)
    print(f"Файл: {store_path}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
