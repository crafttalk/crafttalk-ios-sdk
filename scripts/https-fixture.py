#!/usr/bin/env python3
"""Изолированный HTTPS-стенд: только синтетические данные и loopback-сокеты."""

import base64
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import ssl
import subprocess
import threading


def certificates(directory, resources):
    directory, resources = Path(directory), Path(resources)
    now = datetime.now(timezone.utc)

    def openssl(*args):
        try:
            subprocess.run(["openssl", *map(str, args)], check=True, capture_output=True)
        except subprocess.CalledProcessError as error:
            raise RuntimeError(error.stderr.decode(errors="replace")) from error

    def issue(name, issuer=None, ca=False, san="DNS:localhost,IP:127.0.0.1", offset=0):
        key, pem = directory / (name + ".key"), directory / (name + ".pem")
        config = directory / (name + ".cnf")
        extensions = ("basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n" if ca else
                      "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n"
                      "extendedKeyUsage=serverAuth\nsubjectAltName=" + san + "\n")
        config.write_text("[req]\ndistinguished_name=dn\nprompt=no\n[dn]\nO=CraftTalk SYNTHETIC TEST ONLY\n"
                          f"CN={name}\n[cert]\n{extensions}subjectKeyIdentifier=hash\n")
        csr = directory / (name + ".csr")
        openssl("req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", csr, "-config", config)
        if issuer is None:
            openssl("x509", "-req", "-in", csr, "-signkey", key, "-days", "30", "-sha256",
                    "-extfile", config, "-extensions", "cert", "-out", pem)
        else:
            ca_config = directory / (issuer + "-ca.cnf")
            if not ca_config.exists():
                (directory / (issuer + ".index")).write_text("")
                (directory / (issuer + ".serial")).write_text("01\n")
                ca_config.write_text(f"[ca]\ndefault_ca=CA\n[CA]\ndatabase={directory / (issuer + '.index')}\n"
                                     f"serial={directory / (issuer + '.serial')}\nnew_certs_dir={directory}\n"
                                     f"certificate={directory / (issuer + '.pem')}\nprivate_key={directory / (issuer + '.key')}\n"
                                     "default_md=sha256\npolicy=policy\nunique_subject=no\n[policy]\ncommonName=supplied\n")
            start = now + timedelta(days=offset - 1)
            end = now + timedelta(days=offset + (20 if ca else 7))
            openssl("ca", "-batch", "-notext", "-config", ca_config, "-in", csr, "-out", pem,
                    "-startdate", start.strftime("%Y%m%d%H%M%SZ"), "-enddate", end.strftime("%Y%m%d%H%M%SZ"),
                    "-extfile", config, "-extensions", "cert")
        openssl("x509", "-in", pem, "-outform", "DER", "-out", resources / (name + ".der"))

    for name in ["root", "other-root", "system-root"]:
        issue(name, ca=True)
    issue("intermediate", "root", ca=True)
    issue("missing-intermediate", "root", ca=True)
    for name in ["valid", "renewed"]:
        issue(name, "intermediate")
    issue("wrong-host", "intermediate", san="DNS:wrong.invalid")
    issue("expired", "intermediate", offset=-30)
    issue("future", "intermediate", offset=10)
    issue("missing", "missing-intermediate")
    issue("untrusted", "other-root")
    issue("system", "system-root")
    for name in ["valid", "renewed", "wrong-host", "expired", "future", "missing", "untrusted", "system"]:
        chain = (directory / (name + ".pem")).read_bytes()
        if name in ["valid", "renewed", "wrong-host", "expired", "future"]:
            chain += (directory / "intermediate.pem").read_bytes()
        (directory / (name + "-chain.pem")).write_bytes(chain)
    return now.timestamp() + 2


class Fixture:
    def __init__(self, directory, resources, log_path, *, hold_timeout=15, body_timeout=30):
        self.condition = threading.Condition()
        self.cases = {}
        self.closing = False
        self.errors = []
        self.error_path = Path(log_path).with_name("fixture-errors.json")
        self.error_path.write_text("[]\n")
        self.servers = []
        self.threads = []
        self.log = Path(log_path).open("w")
        self.verify_time = certificates(directory, resources)
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *args):
                pass

            def send(self, status, data, headers=None):
                self.send_response(status)
                for key, value in (headers or {}).items():
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)
                self.close_connection = True

            def do_GET(self):
                self.handle_request()

            def do_POST(self):
                self.handle_request()

            # Probe тоже должен попадать в журнал одноразовых URL.
            def do_HEAD(self):
                self.handle_request()

            def handle_request(self):
                try:
                    self.route_request()
                except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                    self.close_connection = True

            def route_request(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                parts = self.path.split("/", 3)
                if len(parts) < 3:
                    self.send(404, b"")
                    return
                identifier = parts[2]
                if parts[1] == "control" and self.command == "POST":
                    command = json.loads(body)
                    with fixture.condition:
                        if command.get("reset"):
                            previous = fixture.cases.pop(identifier, None)
                            if previous:
                                previous["cancelled"] = True
                                fixture.condition.notify_all()
                        case = fixture.cases.setdefault(identifier, {"routes": {}, "requests": [], "released": set()})
                        if "hostCommand" in command:
                            case["hostCommand"] = command["hostCommand"]
                        if "snapshot" in command:
                            case["snapshot"] = command["snapshot"]
                        if "routes" in command:
                            case["routes"].update(command["routes"])
                        if "release" in command:
                            case["released"].add(command["release"])
                            fixture.condition.notify_all()
                        if "wait" in command:
                            route = command["wait"]
                            fixture.condition.wait_for(lambda: any(r["route"] == route for r in case["requests"]), timeout=10)
                        if "snapshot" in command:
                            result = [{"hostCommand": case.pop("hostCommand", "")}]
                        else:
                            result = [case.get("snapshot", {})] if command.get("state") else case["requests"]
                        data = json.dumps(result).encode()
                    self.send(200, data, {"Content-Type": "application/json"})
                    return
                if parts[1] != "case" or len(parts) < 4:
                    self.send(404, b"")
                    return
                route = parts[3]
                with fixture.condition:
                    case = fixture.cases.get(identifier)
                    if case is None:
                        self.send(404, b"")
                        return
                    record = {"route": route, "method": self.command, "host": self.headers.get("Host"),
                              "body": base64.b64encode(body).decode(), "headers": {k.lower(): v for k, v in self.headers.items()}}
                    case["requests"].append(record)
                    fixture.log.write(json.dumps({"case": identifier, **record}) + "\n")
                    fixture.log.flush()
                    fixture.condition.notify_all()
                    spec = case["routes"].get(route, {"status": 404})
                    if spec.get("oneUse") and sum(r["route"] == route for r in case["requests"]) > 1:
                        spec = {"status": 410}
                    if spec.get("hold"):
                        if not fixture.wait_for_release(case, identifier, route, "hold", hold_timeout):
                            self.close_connection = True
                            return
                if spec.get("disconnect"):
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.close_connection = True
                    return
                payload = base64.b64decode(spec.get("body", ""))
                if self.command == "HEAD":
                    self.send(spec.get("status", 200), payload, spec.get("headers"))
                    return
                if spec.get("truncate") and not spec.get("holdAfterHeaders"):
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(payload) + 100))
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.wfile.write(payload)
                    self.wfile.flush()
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.close_connection = True
                    return
                if spec.get("holdAfterHeaders"):
                    self.send_response(spec.get("status", 200))
                    for key, value in spec.get("headers", {}).items():
                        self.send_header(key, value)
                    self.send_header("Content-Length", str(len(payload) + (100 if spec.get("truncate") else 0)))
                    self.send_header("Connection", "close")
                    self.end_headers()
                    # WebKit должен распознать ответ до остановки оставшегося тела.
                    prefix = min(4096, max(0, len(payload) - 1))
                    self.wfile.write(payload[:prefix])
                    self.wfile.flush()
                    if not fixture.wait_for_release(case, identifier, route, "holdAfterHeaders", body_timeout):
                        self.close_connection = True
                        return
                    self.wfile.write(payload[prefix:])
                    self.close_connection = True
                else:
                    self.send(spec.get("status", 200), payload, spec.get("headers"))

        self.ports = {}
        for name in ["valid", "renewed", "wrong-host", "expired", "future", "missing", "untrusted", "system", "http"]:
            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            server.daemon_threads = True
            if name != "http":
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.minimum_version = ssl.TLSVersion.TLSv1_2
                context.load_cert_chain(str(Path(directory) / (name + "-chain.pem")), str(Path(directory) / (name + ".key")))
                server.socket = context.wrap_socket(server.socket, server_side=True)
            self.ports[name] = server.server_port
            self.servers.append(server)
            thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
            thread.start()
            self.threads.append(thread)
        (Path(resources) / "config.json").write_text(json.dumps({"ports": self.ports, "verifyTime": self.verify_time}))

    def wait_for_release(self, case, identifier, route, phase, timeout):
        with self.condition:
            ready = self.condition.wait_for(
                lambda: route in case["released"] or case.get("cancelled", False) or self.closing,
                timeout=timeout)
            if not ready:
                # Таймаут барьера — ошибка стенда, а не разрешение успешно закончить ответ.
                self.errors.append({"case": identifier, "route": route, "phase": phase,
                                    "error": "release-timeout", "timeoutSeconds": timeout})
                self.error_path.write_text(json.dumps(self.errors, indent=2) + "\n")
            return ready and not self.closing and not case.get("cancelled", False)

    def close(self):
        with self.condition:
            if self.closing:
                return
            self.closing = True
            # Уборка прерывает ожидания без успешной отправки тела и без новых ошибок таймаута.
            self.condition.notify_all()
        for server in self.servers:
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(timeout=2)
        self.log.close()
