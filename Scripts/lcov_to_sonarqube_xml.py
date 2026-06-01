#!/usr/bin/env python3
"""Convert lcov coverage report to SonarQube generic coverage XML."""
from __future__ import annotations

import os
import posixpath
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict


def normalize_path(raw_path: str, prefix: str) -> str:
    path = raw_path.strip().replace("\\", "/")
    if path.startswith(prefix):
        path = path[len(prefix):]
    return posixpath.normpath(path)


def convert(lcov_path: str, xml_path: str) -> None:
    prefix = os.environ.get("GITHUB_WORKSPACE", os.getcwd()).rstrip("/").replace("\\", "/") + "/"
    # file -> line -> hit count
    hits_by_file: dict[str, dict[int, int]] = defaultdict(dict)
    current_file: str | None = None

    with open(lcov_path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("SF:"):
                current_file = normalize_path(line[3:], prefix)
            elif line.startswith("DA:") and current_file is not None:
                parts = line[3:].split(",")
                if len(parts) < 2:
                    continue
                try:
                    line_no = int(parts[0])
                    hit_count = int(parts[1])
                except ValueError:
                    continue
                if line_no <= 0:
                    continue
                # Keep max hit count if line appears multiple times.
                existing = hits_by_file[current_file].get(line_no)
                if existing is None:
                    hits_by_file[current_file][line_no] = hit_count
                elif hit_count > existing:
                    hits_by_file[current_file][line_no] = hit_count

    root = ET.Element("coverage", version="1")
    for path in sorted(hits_by_file):
        if not path.startswith("Sources/"):
            continue
        file_elem = ET.SubElement(root, "file", path=path)
        for line_no in sorted(hits_by_file[path]):
            ET.SubElement(
                file_elem,
                "lineToCover",
                lineNumber=str(line_no),
                covered="true" if hits_by_file[path][line_no] > 0 else "false",
            )

    ET.ElementTree(root).write(xml_path, encoding="utf-8", xml_declaration=True)

    files = root.findall("file")
    total = sum(len(file_elem.findall("lineToCover")) for file_elem in files)
    covered = sum(
        1
        for file_elem in files
        for line_elem in file_elem.findall("lineToCover")
        if line_elem.get("covered") == "true"
    )
    print(f"Prefix stripped : {prefix}")
    print(f"Files           : {len(files)}")
    print(f"Lines           : {total} total, {covered} covered")
    print(f"Output          : {xml_path}")


if __name__ == "__main__":
    lcov = sys.argv[1] if len(sys.argv) > 1 else "coverage.lcov"
    out = sys.argv[2] if len(sys.argv) > 2 else "coverage.xml"
    convert(lcov, out)
