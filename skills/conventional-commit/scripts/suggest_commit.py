#!/usr/bin/env python3
"""
Analyze git diff and suggest a conventional commit message.
Reads from stdin (git diff --cached output) and outputs suggested message.
"""

import sys
import re
from collections import defaultdict


def analyze_diff(diff_text: str) -> tuple[str, str, str]:
    """Return (type, scope, subject) for the given diff."""
    file_patterns = defaultdict(int)
    line_stats = {"added": 0, "removed": 0}
    added_lines = []
    removed_lines = []

    for line in diff_text.split("\n"):
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+") and not line.startswith("+++"):
            line_stats["added"] += 1
            added_lines.append(line[1:].strip())
        elif line.startswith("-") and not line.startswith("---"):
            line_stats["removed"] += 1
            removed_lines.append(line[1:].strip())

    files = extract_files_from_diff(diff_text)

    commit_type = detect_type(files, added_lines, removed_lines)
    scope = detect_scope(files)
    subject = generate_subject(commit_type, files, added_lines, removed_lines)

    return commit_type, scope, subject


def extract_files_from_diff(diff_text: str) -> list[str]:
    files = []
    for line in diff_text.split("\n"):
        # "diff --git a/path b/path" — take the b/ side, strip the prefix
        if line.startswith("diff --git"):
            parts = line.split(" ")
            if len(parts) >= 4:
                files.append(parts[3][2:])
    return files


def detect_type(files: list[str], added: list[str], removed: list[str]) -> str:
    is_test = all(is_test_file(f) for f in files)
    is_doc = all(is_doc_file(f) for f in files)
    is_ci = all(is_ci_file(f) for f in files)
    is_config = all(is_config_file(f) for f in files)

    if is_test:
        return "test"
    if is_doc:
        return "docs"
    if is_ci:
        return "ci"
    if is_config:
        return "chore"

    if detect_bugfix(added, removed):
        return "fix"

    if detect_refactor(files, added, removed):
        return "refactor"

    return "feat"


def is_test_file(path: str) -> bool:
    test_patterns = [
        r"test/",
        r"tests/",
        r"_test\.py$",
        r"\.test\.js$",
        r"\.test\.ts$",
        r"_spec\.py$",
    ]
    return any(re.search(pattern, path) for pattern in test_patterns)


def is_doc_file(path: str) -> bool:
    doc_patterns = [
        r"\.md$",
        r"docs/",
        r"README",
        r"CHANGELOG",
        r"\.rst$",
    ]
    return any(re.search(pattern, path) for pattern in doc_patterns)


def is_ci_file(path: str) -> bool:
    ci_patterns = [
        r"\.github/",
        r"\.gitlab-ci\.yml",
        r"Dockerfile",
        r"docker-compose",
        r"\.circleci/",
    ]
    return any(re.search(pattern, path) for pattern in ci_patterns)


def is_config_file(path: str) -> bool:
    config_patterns = [
        r"package\.json",
        r"pyproject\.toml",
        r"requirements\.txt",
        r"Makefile",
        r"\.env",
        r"setup\.py",
        r"go\.mod",
        r"Gemfile",
    ]
    return any(re.search(pattern, path) for pattern in config_patterns)


def detect_bugfix(added: list[str], removed: list[str]) -> bool:
    """Heuristic: if more lines removed than added, likely a fix."""
    return len(removed) > len(added) * 1.5


def detect_refactor(files: list[str], added: list[str], removed: list[str]) -> bool:
    """Heuristic: much more removed than added tends to mean cleanup/refactor."""
    return len(removed) > len(added) * 2


def detect_scope(files: list[str]) -> str:
    if not files:
        return ""

    for file_path in files:
        parts = file_path.split("/")
        if len(parts) >= 2:
            if parts[0] in ["src", "lib", "app", "packages"]:
                return parts[1]
            return parts[0]
    return ""


def generate_subject(
    commit_type: str, files: list[str], added: list[str], removed: list[str]
) -> str:
    """Generate a concise subject line."""
    subjects = {
        "feat": "add new feature",
        "fix": "fix issue",
        "refactor": "refactor code",
        "docs": "update documentation",
        "test": "add tests",
        "chore": "update dependencies",
        "ci": "update ci configuration",
    }

    base = subjects.get(commit_type, "make changes")

    if commit_type == "test" and files:
        return f"add tests for {files[0].split('/')[-1]}"
    if commit_type == "docs" and files:
        doc_file = files[0].split("/")[-1].replace(".md", "")
        return f"update {doc_file}"
    if commit_type == "feat" and files:
        if "skills/" in files[0]:
            skill_name = files[0].split("/")[1]
            return f"add {skill_name} skill"

    return base


def main():
    diff_text = sys.stdin.read()

    if not diff_text.strip():
        print("error: no staged changes")
        sys.exit(1)

    try:
        commit_type, scope, subject = analyze_diff(diff_text)

        if scope:
            message = f"{commit_type}({scope}): {subject}"
        else:
            message = f"{commit_type}: {subject}"

        print(message)
    except Exception as e:
        print(f"error: failed to analyze diff: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
