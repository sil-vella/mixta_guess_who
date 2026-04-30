#!/usr/bin/env python3
"""CLI editor for celeb YAML datasets used by QuestionModule.

This script keeps these files in sync:
- plugins/game_plugin/modules/question_module/celeb_data/celeb_data.yml
- plugins/game_plugin/modules/question_module/celeb_data/categoriesed_celeb_names_for_db_populate.yml

Usage examples:
  python tools/celeb_yaml_editor.py view --level 1
  python tools/celeb_yaml_editor.py edit --level 2
  python tools/celeb_yaml_editor.py edit
"""

from __future__ import annotations

import argparse
import copy
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Optional

import yaml


SCRIPT_DIR = Path(__file__).resolve().parent
QUESTION_MODULE_DIR = SCRIPT_DIR.parent / "plugins" / "game_plugin" / "modules" / "question_module"
CELEB_DATA_PATH = QUESTION_MODULE_DIR / "celeb_data" / "celeb_data.yml"
NAMES_DATA_PATH = QUESTION_MODULE_DIR / "celeb_data" / "categoriesed_celeb_names_for_db_populate.yml"


def _read_yaml(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        loaded = yaml.safe_load(handle)
    if loaded is None:
        return {}
    if not isinstance(loaded, dict):
        raise ValueError(f"Expected top-level mapping in {path}, found {type(loaded).__name__}")
    return loaded


def _backup_file(path: Path) -> Path:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = path.with_suffix(path.suffix + f".bak_{ts}")
    backup_path.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return backup_path


def _write_yaml(path: Path, data: Mapping[str, Any]) -> None:
    if path.exists():
        _backup_file(path)
    rendered = yaml.safe_dump(
        data,
        sort_keys=True,
        allow_unicode=True,
        default_flow_style=False,
        width=120,
    )
    path.write_text(rendered, encoding="utf-8")


def _normalize_categories(categories: Any) -> List[str]:
    if categories is None:
        return []
    if not isinstance(categories, list):
        raise ValueError("categories must be a list")
    result: List[str] = []
    for item in categories:
        if item is None:
            continue
        value = str(item).strip()
        if value and value not in result:
            result.append(value)
    return result


def _normalize_facts(facts: Any) -> List[str]:
    if facts is None:
        return []
    if not isinstance(facts, list):
        raise ValueError("facts must be a list")
    result: List[str] = []
    for item in facts:
        if item is None:
            continue
        value = str(item).strip()
        if value:
            result.append(value)
    return result


def _collect_names_categories(level_names_data: Any) -> Dict[str, List[str]]:
    if not isinstance(level_names_data, dict):
        return {}
    categories: Dict[str, List[str]] = {}
    for category, celeb_list in level_names_data.items():
        if not isinstance(celeb_list, list):
            continue
        for celeb in celeb_list:
            celeb_name = str(celeb).strip()
            if not celeb_name:
                continue
            categories.setdefault(celeb_name, [])
            if category not in categories[celeb_name]:
                categories[celeb_name].append(str(category))
    return categories


def build_merged_view(
    celeb_data: Mapping[str, Any],
    names_data: Mapping[str, Any],
    levels: Optional[Iterable[str]] = None,
) -> Dict[str, Dict[str, Dict[str, List[str]]]]:
    wanted_levels = set(levels or [])
    all_levels = set(str(k) for k in celeb_data.keys()) | set(str(k) for k in names_data.keys())
    if wanted_levels:
        all_levels = all_levels | wanted_levels

    merged: Dict[str, Dict[str, Dict[str, List[str]]]] = {}
    for level in sorted(all_levels, key=lambda x: int(x) if x.isdigit() else x):
        level_celeb_data = celeb_data.get(level, {})
        level_names_data = names_data.get(level, {})

        if not isinstance(level_celeb_data, dict):
            level_celeb_data = {}

        names_categories = _collect_names_categories(level_names_data)
        celeb_names = set(level_celeb_data.keys()) | set(names_categories.keys())

        merged[level] = {}
        for celeb_name in sorted(celeb_names):
            celeb_row = level_celeb_data.get(celeb_name, {})
            celeb_categories = _normalize_categories(celeb_row.get("categories") if isinstance(celeb_row, dict) else [])
            celeb_facts = _normalize_facts(celeb_row.get("facts") if isinstance(celeb_row, dict) else [])

            fallback_categories = names_categories.get(celeb_name, [])
            if not celeb_categories and fallback_categories:
                celeb_categories = fallback_categories

            merged[level][celeb_name] = {
                "categories": celeb_categories,
                "facts": celeb_facts,
            }
    return merged


def _validate_edited_view(edited: Any) -> Dict[str, Dict[str, Dict[str, List[str]]]]:
    if not isinstance(edited, dict):
        raise ValueError("Edited content must be a top-level mapping of levels")

    normalized: Dict[str, Dict[str, Dict[str, List[str]]]] = {}
    for level, level_data in edited.items():
        level_key = str(level)
        if level_data is None:
            normalized[level_key] = {}
            continue
        if not isinstance(level_data, dict):
            raise ValueError(f"Level '{level_key}' must map celeb_name -> data")

        normalized[level_key] = {}
        for celeb_name, celeb_row in level_data.items():
            celeb_key = str(celeb_name).strip()
            if not celeb_key:
                continue
            if celeb_row is None:
                celeb_row = {}
            if not isinstance(celeb_row, dict):
                raise ValueError(f"Celeb '{celeb_key}' in level '{level_key}' must be a mapping")

            categories = _normalize_categories(celeb_row.get("categories"))
            facts = _normalize_facts(celeb_row.get("facts"))
            normalized[level_key][celeb_key] = {
                "categories": categories,
                "facts": facts,
            }
    return normalized


def _rebuild_names_for_level(level_celeb_data: Mapping[str, Any]) -> Dict[str, List[str]]:
    by_category: Dict[str, List[str]] = {}
    for celeb_name, celeb_row in level_celeb_data.items():
        if not isinstance(celeb_row, dict):
            continue
        categories = _normalize_categories(celeb_row.get("categories"))
        for category in categories:
            by_category.setdefault(category, [])
            if celeb_name not in by_category[category]:
                by_category[category].append(celeb_name)

    for category in by_category:
        by_category[category].sort()
    return dict(sorted(by_category.items(), key=lambda item: item[0]))


def apply_edited_view(
    celeb_data: MutableMapping[str, Any],
    names_data: MutableMapping[str, Any],
    edited_view: Mapping[str, Any],
) -> None:
    validated = _validate_edited_view(edited_view)

    for level, level_rows in validated.items():
        celeb_data[level] = {}
        for celeb_name, celeb_row in sorted(level_rows.items(), key=lambda item: item[0]):
            celeb_data[level][celeb_name] = {
                "categories": celeb_row["categories"],
                "facts": celeb_row["facts"],
            }

        names_data[level] = _rebuild_names_for_level(celeb_data[level])


def _open_editor(file_path: Path) -> None:
    editor = os.environ.get("EDITOR")
    if editor:
        cmd = [editor, str(file_path)]
    else:
        cmd = ["vi", str(file_path)]
    subprocess.run(cmd, check=True)


def _dump_yaml_to_stdout(data: Mapping[str, Any]) -> None:
    print(
        yaml.safe_dump(
            data,
            sort_keys=True,
            allow_unicode=True,
            default_flow_style=False,
            width=120,
        )
    )


def _parse_levels(raw_levels: Optional[List[str]]) -> Optional[List[str]]:
    if not raw_levels:
        return None
    return [str(x).strip() for x in raw_levels if str(x).strip()]


def cmd_view(args: argparse.Namespace) -> int:
    celeb_data = _read_yaml(CELEB_DATA_PATH)
    names_data = _read_yaml(NAMES_DATA_PATH)
    levels = _parse_levels(args.level)
    merged = build_merged_view(celeb_data, names_data, levels=levels)
    _dump_yaml_to_stdout(merged)
    return 0


def cmd_edit(args: argparse.Namespace) -> int:
    celeb_data = _read_yaml(CELEB_DATA_PATH)
    names_data = _read_yaml(NAMES_DATA_PATH)

    original_celeb_data = copy.deepcopy(celeb_data)
    original_names_data = copy.deepcopy(names_data)

    levels = _parse_levels(args.level)
    merged = build_merged_view(celeb_data, names_data, levels=levels)

    with tempfile.NamedTemporaryFile("w+", suffix=".yml", delete=False, encoding="utf-8") as temp_file:
        tmp_path = Path(temp_file.name)
        temp_file.write(
            yaml.safe_dump(
                merged,
                sort_keys=True,
                allow_unicode=True,
                default_flow_style=False,
                width=120,
            )
        )
        temp_file.flush()

    try:
        _open_editor(tmp_path)
        edited = _read_yaml(tmp_path)
    finally:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass

    apply_edited_view(celeb_data, names_data, edited)

    if celeb_data == original_celeb_data and names_data == original_names_data:
        print("No changes detected.")
        return 0

    _write_yaml(CELEB_DATA_PATH, celeb_data)
    _write_yaml(NAMES_DATA_PATH, names_data)
    print("Updated YAML files successfully.")
    print(f"- {CELEB_DATA_PATH}")
    print(f"- {NAMES_DATA_PATH}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Edit celeb_data.yml and categoriesed_celeb_names_for_db_populate.yml together."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    view_parser = subparsers.add_parser("view", help="Print merged data view (levels -> celeb -> categories/facts)")
    view_parser.add_argument(
        "--level",
        action="append",
        help="Limit to one or more levels (repeatable), e.g. --level 1 --level 2",
    )
    view_parser.set_defaults(func=cmd_view)

    edit_parser = subparsers.add_parser(
        "edit",
        help="Open merged YAML in $EDITOR, then apply changes back to both source files",
    )
    edit_parser.add_argument(
        "--level",
        action="append",
        help=(
            "Edit only selected levels (repeatable). Missing selected levels are created. "
            "Without this flag, all levels are editable."
        ),
    )
    edit_parser.set_defaults(func=cmd_edit)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    try:
        parser = build_parser()
        args = parser.parse_args(argv)
        return args.func(args)
    except KeyboardInterrupt:
        print("Cancelled by user.", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
