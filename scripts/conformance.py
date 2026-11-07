"""Pinned upstream audit. Expected normal forms are never beta-normalized.
The regression profile lists exact cases; --audit measures the larger corpus.
Requires git, Node.js and a built MoonBit JS bridge. No upstream code is copied.
"""
from pathlib import Path
from collections import Counter, defaultdict
import argparse
import json
import subprocess
from urllib.parse import urljoin, urlparse, unquote
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
            parent, written = key.split("\n", 1)
            location = urljoin(parent, written)
            source = None
            if location.startswith("file:"):
                file = Path(url2pathname(urlparse(location).path)).resolve()
                # Upstream tests must never read unrelated host files.
                if file.is_relative_to(corpus_root) and file.is_file() and file.stat().st_size <= 262144:
                    try:
                        source = file.read_text(encoding="utf-8")
                    except UnicodeDecodeError:
                        pass
            elif location == "env:DHALL_TEST_VAR":
                source = "6 * 7"
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
                case = file.relative_to(base).as_posix()
                if profile is not None and case not in profile:
                    continue
                jobs.append((case, suite, outcome, file))
    requests, plans, results = [], [], []
    def add(op, source):
        index = len(requests)
        requests.append({"op": op, "source": source, "origin": origin})
        return index
    for case, suite, outcome, file in jobs:
        origin = file.resolve().as_uri()
        if suite == "import":
            results.append({"case": case, "status": "not-run", "reason": "Requires upstream HTTP/CORS/header/cache fixture server; host imports have separate integration tests"})
            continue
        try:
            source = file.read_bytes().hex() if suite == "binary-decode" else file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            results.append({"case": case, "status": "pass" if suite == "parser" and outcome == "failure" else "fail",
                            "reason": "UTF-8 transport rejects malformed bytes before parsing"})
            continue
        if outcome == "failure":
            op = {"parser": "syntax", "type-inference": "check", "binary-decode": "decode"}.get(suite)
            if op is None:
                results.append({"case": case, "status": "not-run", "reason": "No failure-suite adapter"})
                continue
            inputs = [add(op, source)]
            if suite == "type-inference":
                inputs.append(add("syntax", source))
            plans.append((case, "reject", inputs, None))
            continue
        prefix = str(file)[:-len("A.dhallb" if suite == "binary-decode" else "A.dhall")]
        if suite == "parser":
            plans.append((case, "equal", [add("parse", source)], Path(prefix + "B.dhallb").read_bytes().hex()))
        elif suite == "semantic-hash":
            expected = Path(prefix + "B.hash").read_text().strip().removeprefix("sha256:")
            plans.append((case, "equal", [add("hash", source)], expected))
        elif suite in ["normalization", "alpha-normalization", "type-inference"]:
            expected = Path(prefix + "B.dhall").read_text(encoding="utf-8")
            op = {"normalization": "beta-resolved", "alpha-normalization": "alpha", "type-inference": "type-binary"}[suite]
            plans.append((case, "compare", [add(op, source), add("alpha", expected)], None))
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
