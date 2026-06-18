#!/usr/bin/env python3
"""Update image.repository and image.tag in an NQLabs service environment file.

This intentionally uses a small line-preserving updater instead of a YAML dumping
library so comments/order/formatting in environment files stay stable.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def update_image(path: Path, repository: str, tag: str) -> bool:
    lines = path.read_text().splitlines(keepends=True)

    image_idx = None
    for i, line in enumerate(lines):
        if line.strip() == "image:" and not line.startswith((" ", "\t")):
            image_idx = i
            break

    if image_idx is None:
        raise SystemExit(f"image: block not found in {path}")

    block_end = len(lines)
    for i in range(image_idx + 1, len(lines)):
        line = lines[i]
        if line.strip() and not line.startswith((" ", "\t")):
            block_end = i
            break

    repo_idx = None
    tag_idx = None
    for i in range(image_idx + 1, block_end):
        stripped = lines[i].strip()
        if stripped.startswith("repository:"):
            repo_idx = i
        elif stripped.startswith("tag:"):
            tag_idx = i

    changed = False

    def set_line(index: int, key: str, value: str) -> None:
        nonlocal changed
        newline = "\n" if lines[index].endswith("\n") else ""
        new_line = f"  {key}: {value}{newline}"
        if lines[index] != new_line:
            lines[index] = new_line
            changed = True

    if repo_idx is None:
        insert_at = image_idx + 1
        lines.insert(insert_at, f"  repository: {repository}\n")
        changed = True
        if tag_idx is not None and tag_idx >= insert_at:
            tag_idx += 1
    else:
        set_line(repo_idx, "repository", repository)

    if tag_idx is None:
        insert_at = (repo_idx + 1) if repo_idx is not None else image_idx + 2
        lines.insert(insert_at, f"  tag: {tag}\n")
        changed = True
    else:
        set_line(tag_idx, "tag", tag)

    if changed:
        path.write_text("".join(lines))
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", required=True, help="Service name under apps/<service>")
    parser.add_argument("--environment", required=True, help="Environment file name, e.g. staging or production")
    parser.add_argument("--repository", required=True, help="Container image repository")
    parser.add_argument("--tag", required=True, help="Container image tag")
    parser.add_argument("--file", type=Path, help="Override target file for tests")
    args = parser.parse_args()

    path = args.file or Path("apps") / args.service / "environments" / f"{args.environment}.yaml"
    if not path.exists():
        raise SystemExit(f"environment file does not exist: {path}")

    changed = update_image(path, args.repository, args.tag)
    status = "updated" if changed else "already up to date"
    print(f"{path}: {status} -> {args.repository}:{args.tag}")


if __name__ == "__main__":
    main()
