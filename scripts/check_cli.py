"""Exercise the real command-line entry point, including failed exit statuses."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run(
        ["moon", "run", "cmd/main", "--target", "js", "--", *args],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=30,
    )


def require(condition, result):
    if not condition:
        raise AssertionError(result.stdout + result.stderr)


def main():
    result = run("json", "let port = 8080 in { port = port }")
    require(result.returncode == 0, result)
    assert json.loads(result.stdout) == {"port": 8080}
    result = run("check", r"\(port : Natural) -> { port = port }")
    require(result.returncode == 0, result)
    assert result.stdout.strip() == "(Natural -> { port : Natural })"
    for source in ["1 + True", '"unterminated', "9223372036854775807 + 1"]:
        result = run("json", source)
        require(result.returncode != 0, result)
    for args in [("unknown", "1"), ("json",)]:
        result = run(*args)
        require(result.returncode != 0, result)
    result = run("--help")
    require(result.returncode == 0 and "Usage:" in result.stdout, result)
    result = run("json", "9007199254740993")
    require(result.returncode == 0, result)
    assert result.stdout.strip() == "9007199254740993"
    print("CLI integration: 9 checks passed")


if __name__ == "__main__":
    main()
