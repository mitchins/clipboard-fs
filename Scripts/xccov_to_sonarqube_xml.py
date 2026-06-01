#!/usr/bin/env python3
"""Convert Xcode .xcresult coverage to SonarQube generic coverage XML."""
from __future__ import annotations

import json
import os
import posixpath
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


LINE_RE = re.compile(r"^\s*(\d+):\s+(\*|\d+)\s*$")


def run(command: list[str]) -> str:
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    return completed.stdout


def workspace_prefix() -> str:
    workspace = os.environ.get("GITHUB_WORKSPACE", os.getcwd()).replace("\\", "/").rstrip("/")
    return workspace + "/"


def normalize_report_path(raw_path: str) -> str:
    path = raw_path.strip().replace("\\", "/")
    prefix = workspace_prefix()
    if path.startswith(prefix):
        path = path[len(prefix) :]
    return posixpath.normpath(path)


def load_archive_ids(xcresult_path: str) -> list[str]:
    output = run([
        "xcrun",
        "xcresulttool",
        "get",
        "object",
        "--legacy",
        "--path",
        xcresult_path,
        "--format",
        "json",
    ])
    data = json.loads(output)

    ids: list[str] = []
    for action in data.get("actions", {}).get("_values", []):
        archive_id = (
            action.get("actionResult", {})
            .get("coverage", {})
            .get("archiveRef", {})
            .get("id", {})
            .get("_value")
        )
        if archive_id and archive_id not in ids:
            ids.append(archive_id)

    if not ids:
        raise RuntimeError(f"No coverage archive references found in {xcresult_path}")

    return ids


def export_archives(xcresult_path: str, archive_ids: list[str], output_dir: str) -> None:
    for archive_id in archive_ids:
        subprocess.run(
            [
                "xcrun",
                "xcresulttool",
                "export",
                "--legacy",
                "--type",
                "directory",
                "--path",
                xcresult_path,
                "--id",
                archive_id,
                "--output-path",
                output_dir,
            ],
            check=True,
        )


def list_files(archive_path: str) -> list[str]:
    output = run(["xcrun", "xccov", "view", "--archive", "--file-list", archive_path])
    return [line.strip() for line in output.splitlines() if line.strip()]


def collect_line_hits(archive_path: str, file_path: str) -> list[tuple[int, bool]]:
    output = run(["xcrun", "xccov", "view", "--archive", "--file", file_path, archive_path])
    line_hits: list[tuple[int, bool]] = []
    for raw_line in output.splitlines():
        match = LINE_RE.match(raw_line)
        if not match:
            continue
        line_number = int(match.group(1))
        hits = match.group(2)
        if hits == "*":
            continue
        line_hits.append((line_number, int(hits) > 0))
    return line_hits


def convert(xcresult_path: str, xml_path: str) -> None:
    archive_ids = load_archive_ids(xcresult_path)

    coverage_by_file: dict[str, list[tuple[int, bool]]] = {}
    with tempfile.TemporaryDirectory() as temp_dir:
        archive_dir = os.path.join(temp_dir, "coverage.xccovarchive")
        os.makedirs(archive_dir, exist_ok=True)
        export_archives(xcresult_path, archive_ids, archive_dir)

        for file_path in list_files(archive_dir):
            report_path = normalize_report_path(file_path)
            if not report_path.startswith("Sources/"):
                continue

            line_hits = collect_line_hits(archive_dir, file_path)
            if line_hits:
                coverage_by_file[report_path] = line_hits

    if not coverage_by_file:
        raise RuntimeError("No source coverage data found under Sources/")

    root = ET.Element("coverage", version="1")
    total_lines = 0
    covered_lines = 0

    for path in sorted(coverage_by_file):
        file_elem = ET.SubElement(root, "file", path=path)
        for line_number, covered in coverage_by_file[path]:
            ET.SubElement(
                file_elem,
                "lineToCover",
                lineNumber=str(line_number),
                covered="true" if covered else "false",
            )
            total_lines += 1
            if covered:
                covered_lines += 1

    ET.ElementTree(root).write(xml_path, encoding="utf-8", xml_declaration=True)

    print(f"Coverage source prefix: {workspace_prefix()}")
    print(f"Files                : {len(coverage_by_file)}")
    print(f"Lines                : {total_lines} total, {covered_lines} covered")
    print(f"Output               : {xml_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("Usage: xccov_to_sonarqube_xml.py <xcresult-path> [output-path]")

    xcresult = sys.argv[1]
    output = sys.argv[2] if len(sys.argv) > 2 else "coverage.xml"
    convert(xcresult, output)
