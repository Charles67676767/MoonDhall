"""Exercise file/stdin/stdout CLI and real HTTP imports against local fixtures."""
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from tempfile import TemporaryDirectory
import json
import os
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/moondhall.mjs"


def run(*args, data=None, env=None):
    return subprocess.run(["node", str(CLI), *map(str, args)], cwd=ROOT,
                          input=data, capture_output=True, timeout=30, env=env)


def require(result, expected=None):
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    if expected is not None:
        assert result.stdout.decode().strip() == expected
    return result.stdout.decode().strip()


def reject(result, message=None):
    assert result.returncode != 0
    assert not result.stdout
    if message:
        assert message in result.stderr.decode()


def main():
    count = 0
    require(run("json", "-e", "9007199254740993"), "9007199254740993"); count += 1
    require(run("json", "-", data=b"{ a = 1 }"), '{"a":1}'); count += 1
    require(run("json", "-e", "9223372036854775807 + 1"), "9223372036854775808"); count += 1
    require(run("check", "-e", r"\(x : Natural) -> x"), "(Natural -> Natural)"); count += 1
    for source in ["1 + True", '"unterminated', "if True then 1 else unknown", "NaN"]:
        reject(run("json", "-e", source)); count += 1
    for arguments in [("unknown",), ("json", "-e"), ("json", "--nonsense")]:
        reject(run(*arguments)); count += 1
    assert "Usage:" in require(run("--help")); count += 1
    reject(run("json", "-", data=b"\xff")); count += 1
    for file in ["examples/imports/main.dhall", "examples/polymorphic/config.dhall"]:
        expected = json.loads((ROOT / file).with_suffix(".json").read_text(encoding="utf-8"))
        actual = json.loads(require(run("json", ROOT / file)))
        assert actual == expected
        count += 1
    (ROOT / ".local").mkdir(exist_ok=True)
    with TemporaryDirectory(prefix="moondhall-test-", dir=ROOT / ".local") as directory:
        temp = Path(directory)
        os.environ["XDG_CACHE_HOME"] = str(temp / "standard-cache")
        os.environ["XDG_CONFIG_HOME"] = str(temp / "standard-config")
        os.environ.pop("DHALL_HEADERS", None)
        (temp / "value.dhall").write_text("{ port = 8080 }")
        (temp / "main.dhall").write_text("./value.dhall")
        require(run("json", temp / "main.dhall"), '{"port":8080}'); count += 1
        output = temp / "config.json"
        require(run("json", temp / "main.dhall", "-o", output), "")
        assert json.loads(output.read_text()) == {"port": 8080}; count += 1
        require(run("encode", temp / "main.dhall", "-o", temp / "value.dhallb"))
        assert (temp / "value.dhallb").read_bytes().startswith(b"\x82\x08")
        decoded = require(run("decode", temp / "value.dhallb"))
        require(run("json", "-e", decoded), '{"port":8080}'); count += 1
        (temp / "bad.dhall").write_text("{ port =\n  True + 1 }")
        reject(run("check", temp / "bad.dhall"), "bad.dhall:2:3"); count += 1
        (temp / "cycle.dhall").write_text("./cycle.dhall")
        reject(run("json", temp / "cycle.dhall"), "Import cycle"); count += 1
        (temp / "bad-import.dhall").write_text("./bad.dhall")
        reject(run("json", temp / "bad-import.dhall"), "Imported from"); count += 1
        require(run("json", "-e", "missing ? 7"), "7"); count += 1

        (temp / "raw bytes.bin").write_bytes(b"\x00\xff")
        (temp / "raw.dhall").write_text('./"raw bytes.bin" as Bytes')
        require(run("json", temp / "raw.dhall"), '"0x00ff"'); count += 1
        require(run("json", "-e", "missing as Location"), '"Missing"'); count += 1
        require(run("json", "-e", 'Time/show 09:00:00.00000000000000000001'),
                '"09:00:00.00000000000000000001"'); count += 1

        requests = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                bodies = {"/root": b"./child", "/child": b"40 + 2", "/remote-env": b"env:MOONDHALL_SECRET"}
                if self.path == "/redirect":
                    self.send_response(302)
                    self.send_header("Location", "/root")
                    self.end_headers()
                    return
                if self.path in {"/with-header", "/inherited-header"} and self.headers.get("Test") == "example":
                    bodies.update({"/with-header": b"./inherited-header", "/inherited-header": b"True"})
                if self.path not in bodies:
                    self.send_response(404); self.end_headers(); return
                self.send_response(200); self.end_headers()
                self.wfile.write(bodies[self.path])
            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = "http://127.0.0.1:" + str(server.server_port)
        cache = temp / "cache"
        try:
            require(run("json", "-e", url + "/unavailable as Location", "--offline"),
                    json.dumps(url + "/unavailable"))
            assert requests == []; count += 1
            require(run("json", "-e", url + '/with-header using (toMap { Test = "example" })', "--no-cache"),
                    "true"); count += 1
            require(run("json", "-e", url + "/redirect", "--no-cache"), "42"); count += 1
            authority = url.split("//", 1)[1]
            env = {**os.environ, "DHALL_HEADERS": 'toMap { ' + chr(96) + authority + chr(96)
                   + ' = toMap { Test = "example" } }'}
            require(run("json", "-e", url + '/with-header using (toMap { Test = "wrong" })',
                        "--no-cache", env=env), "true"); count += 1
            requests.clear()
            digest = require(run("hash", "-e", "42"))
            semantic = temp / "semantic" / "dhall"
            semantic.mkdir(parents=True)
            encoded = run("encode", "-e", "42")
            assert encoded.returncode == 0
            (semantic / ("1220" + digest)).write_bytes(encoded.stdout)
            env = {**os.environ, "XDG_CACHE_HOME": str(semantic.parent)}
            require(run("json", "-e", "missing sha256:" + digest, "--offline", env=env), "42"); count += 1
            pinned = url + "/root sha256:" + digest
            require(run("json", "-e", pinned, "--cache-dir", cache), "42"); count += 1
            assert requests.count("/root") == 1 and requests.count("/child") == 1
            assert (Path(os.environ["XDG_CACHE_HOME"]) / "dhall" / ("1220" + digest)).read_bytes() == encoded.stdout
            require(run("json", "-e", pinned, "--cache-dir", cache, "--offline"), "42")
            assert requests.count("/root") == 1 and requests.count("/child") == 1; count += 1
            wrong = require(run("hash", "-e", "43"))
            reject(run("json", "-e", url + "/root sha256:" + wrong, "--cache-dir", cache), "Integrity mismatch"); count += 1
            require(run("json", "-e", url + "/not-found ? 9", "--cache-dir", cache), "9"); count += 1
            reject(run("json", "-e", url + "/remote-env", "--cache-dir", cache), "cannot access environment"); count += 1
            require(run("json", "-e", url + "/not-cached ? 10", "--cache-dir", cache, "--offline"), "10"); count += 1
        finally:
            server.shutdown(); server.server_close(); thread.join()
    print("CLI integration: " + str(count) + " checks passed")


if __name__ == "__main__":
    main()
