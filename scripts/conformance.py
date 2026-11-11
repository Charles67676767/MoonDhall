"""Pinned upstream audit. Expected normal forms are never beta-normalized.
The regression profile lists exact cases; --audit measures the larger corpus.
Requires git, Node.js and a built MoonBit JS bridge. No upstream code is copied.
"""
from pathlib import Path
from collections import Counter, defaultdict
import argparse
import json
import hashlib
import posixpath
import subprocess
from urllib.parse import urljoin, urlparse, quote, unquote
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "tests/upstream.json").read_text(encoding="utf-8"))
BRIDGE = ROOT / "_build/js/debug/build/cmd/bridge/bridge.js"


def command(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def corpus():
    directory = ROOT / ".local/dhall-standard"
    if not (directory / ".git").exists():
        directory.parent.mkdir(exist_ok=True)
        command("git", "clone", "--no-checkout", "--filter=blob:none", MANIFEST["repository"], str(directory))
    actual = subprocess.check_output(["git", "-C", str(directory), "rev-parse", "HEAD"], text=True).strip()
    if actual != MANIFEST["revision"] or not (directory / "tests").exists():
        command("git", "-C", str(directory), "fetch", "--depth", "1", "origin", MANIFEST["revision"])
        command("git", "-C", str(directory), "checkout", "--detach", MANIFEST["revision"])
    return directory / "tests"


def raw_engine(requests):
    if not requests:
        return []
    result = subprocess.run(["node", str(BRIDGE)], input=json.dumps(requests),
                            capture_output=True, text=True, encoding="utf-8", timeout=60)
    if result.returncode:
        # Isolate crashes so one case cannot hide the remainder of an audit.
        if len(requests) > 1:
            middle = len(requests) // 2
            return raw_engine(requests[:middle]) + raw_engine(requests[middle:])
        return [{"crash": result.stderr[-1000:]}]
    return json.loads(result.stdout)



class UnsupportedFixture(Exception):
    pass


def read_fixture(file, corpus_root, mode):
    if not file.is_relative_to(corpus_root) or not file.is_file() or file.stat().st_size > 262144:
        return None
    if mode == "Bytes":
        return file.read_bytes().hex()
    try:
        return file.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None


def http_fixture(location, parent, headers, corpus_root):
    """Apply the upstream fixture routes in memory, without external requests."""
    url = urlparse(location)
    if url.hostname not in {"localhost", "127.0.0.1"} or url.port not in {18080, 18443}:
        raise UnsupportedFixture("External HTTP fixture is outside the pinned corpus")
    request_headers = {k.lower(): v for k, v in headers}
    cors = None
    if url.path.startswith("/tests/import/"):
        file = (corpus_root / unquote(url.path.lstrip("/"))).resolve()
        body = read_fixture(file, corpus_root, "Text")
        cors = "*"
    elif url.path == "/random-string":
        raise UnsupportedFixture("The upstream random response fixture requires a stateful server")
    elif url.path == "/user-agent":
        body = '{\n  "user-agent": ' + json.dumps(request_headers.get("user-agent", "none_given")) + '\n}\n'
    elif url.path in {"/foo", "/bar"}:
        if request_headers.get("test", "").lower() != "example":
            return None
        body = "./bar" if url.path == "/foo" else "True"
    elif url.path.startswith("/cors/"):
        name = Path(url.path).stem
        cors_cases = {
            "AllowedAll": ("*", "42"),
            "OnlyGithub": ("https://localhost:18443", "42"),
            "OnlyOther": ("https://localhost:28080", "42"),
            "OnlySelf": ("https://127.0.0.1:18443", "42"),
            "Empty": ("", "42"),
            "NoCORS": (None, "42"),
            "Null": ("null", "42"),
            "SelfImportAbsolute": ("*", "https://127.0.0.1:18443/cors/NoCORS.dhall"),
            "SelfImportRelative": ("*", "./NoCORS.dhall"),
            "TwoHopsFail": ("*", "https://localhost:18443/tests/import/data/cors/OnlySelf.dhall"),
            "TwoHopsSuccess": ("*", "https://localhost:18443/tests/import/data/cors/OnlyGithub.dhall"),
        }
        cors, body = cors_cases.get(name, (None, None))
    else:
        return None
    parent_url = urlparse(parent)
    if parent_url.scheme in {"http", "https"}:
        parent_origin = f"{parent_url.scheme}://{parent_url.netloc}"
        if parent_origin != f"{url.scheme}://{url.netloc}" and cors not in {"*", parent_origin}:
            return None
    return body


def fixture_import(key, corpus_root, request):
    parent, written, *metadata = key.split("\n", 2)
    mode, headers, digest = json.loads(metadata[0]) if metadata else ("Code", [], None)
    if digest and mode != "Location":
        file = corpus_root / "tests/import/cache/dhall" / ("1220" + digest)
        if file.is_file():
            binary = file.read_bytes()
            if hashlib.sha256(binary).hexdigest() == digest:
                return "semantic-cache", binary.hex()
    if written == "missing":
        return "missing", None
    if written.startswith("env:"):
        name = written[4:]
        if name.startswith('"'):
            name = json.loads(name)
        if mode == "Location":
            return name, None
        value = request.get("fixture_env", {}).get(name, "6 * 7" if name == "DHALL_TEST_VAR" else None)
        return "env:" + name, value.encode().hex() if mode == "Bytes" and value else value
    remote_parent = parent.startswith(("http://", "https://"))
    if written.startswith(("http://", "https://")) or (remote_parent and written.startswith(("./", "../"))):
        location = urljoin(parent, written)
        url = urlparse(location)
        if mode == "Location":
            segments = []
            for segment in url.path.split("/")[1:]:
                if segment == ".." and segments and segments[-1] != "..":
                    segments.pop()
                elif segment != ".":
                    segments.append(segment)
            normalized = "/" + "/".join(segments)
            if url.path.endswith("/") and not normalized.endswith("/"):
                normalized += "/"
            return url._replace(path=normalized).geturl(), None
        if not request.get("import_fixture"):
            return location, None
        body = http_fixture(location, parent, headers, corpus_root)
        return location, body.encode().hex() if mode == "Bytes" and body is not None else body
    local = "/".join(segment[1:-1] if segment.startswith('"') and segment.endswith('"')
                     else segment for segment in written.split("/"))
    if local.startswith("~/"):
        location = (corpus_root / "tests/import/home" / local[2:]).resolve().as_uri()
    elif local.startswith("/"):
        # Absolute paths in the corpus are intentionally unavailable.
        return local if mode == "Location" else "file://" + quote(local), None
    else:
        location = urljoin(parent, quote(local))
    if not location.startswith("file:"):
        return location, None
    file = Path(url2pathname(urlparse(location).path)).resolve()
    upstream_alias = corpus_root.parent / "dhall-lang"
    if file.is_relative_to(upstream_alias):
        file = corpus_root / file.relative_to(upstream_alias)
        location = file.as_uri()
    if mode == "Location":
        if written.startswith("~/"):
            return "~/" + posixpath.normpath(local[2:]), None
        if file.is_relative_to(corpus_root):
            return "./dhall-lang/" + file.relative_to(corpus_root).as_posix(), None
        return posixpath.normpath(local), None
    return location, read_fixture(file, corpus_root, mode)


def engine(requests):
    pending = list(range(len(requests)))
    results = [None] * len(requests)
    corpus_root = (ROOT / ".local/dhall-standard").resolve()
    for _ in range(128):
        responses = raw_engine([requests[i] for i in pending])
        remaining = []
        for index, response in zip(pending, responses):
            if "need" not in response:
                results[index] = response
                continue
            key = response["need"]
            try:
                location, source = fixture_import(key, corpus_root, requests[index])
            except UnsupportedFixture as error:
                results[index] = {"not-run": str(error)}
                continue
            requests[index].setdefault("sources", []).append({"key": key, "location": location, "source": source})
            remaining.append(index)
        pending = remaining
        if not pending:
            return results
    for i in pending:
        results[i] = {"error": "Import resolution request limit exceeded"}
    return results

def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--audit", action="store_true")
    parser.add_argument("--allow-failures", action="store_true")
    parser.add_argument("--report", default=".local/conformance-report.json")
    args = parser.parse_args()
    base = corpus()
    profile = None if args.audit else set(json.loads((ROOT / "tests/conformance-profile.json").read_text())["cases"])
    jobs = []
    for suite in MANIFEST["suites"]:
        for outcome in ["success", "failure"]:
            folder = base / suite / outcome
            if not folder.exists():
                continue
            files = folder.rglob("*A.dhall") if outcome == "success" else folder.rglob("*.dhall")
            if suite == "binary-decode":
                files = folder.rglob("*A.dhallb") if outcome == "success" else folder.rglob("*.dhallb")
            for file in sorted(files):
                if suite == "import" and file.name.endswith("ENV.dhall"):
                    continue
                case = file.relative_to(base).as_posix()
                if profile is not None and case not in profile:
                    continue
                jobs.append((case, suite, outcome, file))
    requests, plans, results = [], [], []
    def add(op, source):
        index = len(requests)
        request = {"op": op, "source": source, "origin": origin,
                   "import_fixture": suite == "import", "fixture_env": fixture_env}
        if "DHALL_HEADERS" in fixture_env and op in {"check", "beta-resolved"}:
            request["headerSource"] = fixture_env["DHALL_HEADERS"]
            request["headerOrigin"] = (base.parent.parent / "__headers__.dhall").as_uri()
        requests.append(request)
        return index
    for case, suite, outcome, file in jobs:
        origin = file.resolve().as_uri()
        fixture_env = {}
        env_file = file.with_name(file.stem.removesuffix("A") + "ENV.dhall")
        if suite == "import" and env_file.is_file():
            result = engine([{"op": "json", "source": env_file.read_text(encoding="utf-8"),
                              "origin": env_file.resolve().as_uri()}])[0]
            if "result" not in result:
                results.append({"case": case, "status": "not-run", "reason": "Could not evaluate fixture environment"})
                continue
            fixture_env = {p["mapKey"]: p["mapValue"] for p in json.loads(result["result"])}
        try:
            source = file.read_bytes().hex() if suite == "binary-decode" else file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            results.append({"case": case, "status": "pass" if suite == "parser" and outcome == "failure" else "fail",
                            "reason": "UTF-8 transport rejects malformed bytes before parsing"})
            continue
        if outcome == "failure":
            op = {"parser": "syntax", "type-inference": "check", "binary-decode": "decode", "import": "check"}.get(suite)
            if op is None:
                results.append({"case": case, "status": "not-run", "reason": "No failure-suite adapter"})
                continue
            inputs = [add(op, source)]
            if suite in {"type-inference", "import"}:
                inputs.append(add("syntax", source))
            plans.append((case, "reject", inputs, None))
            continue
        prefix = str(file)[:-len("A.dhallb" if suite == "binary-decode" else "A.dhall")]
        if suite == "parser":
            plans.append((case, "equal", [add("parse", source)], Path(prefix + "B.dhallb").read_bytes().hex()))
        elif suite == "semantic-hash":
            expected = Path(prefix + "B.hash").read_text().strip().removeprefix("sha256:")
            plans.append((case, "equal", [add("hash", source)], expected))
        elif suite in ["normalization", "alpha-normalization", "type-inference", "import"]:
            expected = Path(prefix + "B.dhall").read_text(encoding="utf-8")
            op = {"normalization": "beta-resolved", "alpha-normalization": "alpha", "type-inference": "type-binary", "import": "beta-resolved"}[suite]
            plans.append((case, "compare", [add(op, source), add("beta" if suite == "import" else "alpha", expected)], None))
        elif suite == "binary-decode":
            # The decoder must accept oversized float encodings too. Compare the
            # decoded syntax with B, never require byte identity with input A.
            expected = Path(prefix + "B.dhall").read_text(encoding="utf-8")
            plans.append((case, "decode", [add("decode", source), add("parse", expected)], None))
    responses = []
    for start in range(0, len(requests), 32):
        responses.extend(engine(requests[start:start+32]))
    decode_plans, decode_requests = [], []
    for case, mode, indexes, expected in plans:
        values = [responses[i] for i in indexes]
        if any("not-run" in x for x in values):
            results.append({"case": case, "status": "not-run",
                            "reason": next(x["not-run"] for x in values if "not-run" in x)})
            continue
        if mode == "decode" and all("result" in x for x in values):
            decode_plans.append((case, values[1]["result"]))
            decode_requests.append({"op": "parse", "source": values[0]["result"]})
            continue
        if mode == "reject":
            passed = "error" in values[0] and (len(values) == 1 or "result" in values[1])
        elif mode == "compare":
            passed = all("result" in x for x in values) and values[0]["result"] == values[1]["result"]
        else:
            passed = "result" in values[0] and values[0]["result"] == expected
        entry = {"case": case, "status": "pass" if passed else "fail"}
        if not passed:
            entry["actual"] = values
            if expected is not None:
                entry["expected"] = expected
        results.append(entry)
    decoded = []
    for start in range(0, len(decode_requests), 32):
        decoded.extend(engine(decode_requests[start:start+32]))
    for (case, expected), actual in zip(decode_plans, decoded):
        passed = actual.get("result") == expected
        entry = {"case": case, "status": "pass" if passed else "fail"}
        if not passed:
            entry.update(actual=actual, expected=expected)
        results.append(entry)
    counts = Counter(x["status"] for x in results)
    by_suite = defaultdict(Counter)
    for x in results:
        by_suite[x["case"].split("/")[0]][x["status"]] += 1
    report = {"revision": MANIFEST["revision"], "scope": "audit" if args.audit else "regression-profile",
              "counts": dict(counts), "suites": {k: dict(v) for k, v in by_suite.items()}, "results": results}
    target = ROOT / args.report
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "results"}, indent=2))
    if profile is not None and set(x["case"] for x in results) != profile:
        raise SystemExit("Regression profile contains missing cases")
    if counts["fail"] and not args.allow_failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
