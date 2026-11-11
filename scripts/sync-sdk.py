#!/usr/bin/env python3
"""Проверка или синхронизация Swift-исходников SDK без удаления файлов."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "CTChat"
DESTINATION = ROOT / "Example/Chat/CTChat"


def swift_files(directory):
    files = {}
    for path in directory.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Символическая ссылка недопустима в копии SDK: {path}")
        if path.is_file() and path.suffix == ".swift":
            files[path.relative_to(directory)] = path
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Проверить без изменений")
    mode.add_argument("--sync", action="store_true", help="Скопировать изменения из CTChat")
    args = parser.parse_args()

    for directory in (SOURCE, DESTINATION):
        if not directory.is_dir() or directory.resolve() != directory:
            raise ValueError(f"Ожидался каталог SDK: {directory}")
    source, destination = swift_files(SOURCE), swift_files(DESTINATION)
    if not source:
        raise ValueError("В CTChat не найдены Swift-файлы")

    missing = source.keys() - destination.keys()
    extra = destination.keys() - source.keys()
    changed = {name for name in source.keys() & destination.keys()
               if source[name].read_bytes() != destination[name].read_bytes()}
    for label, names in (("Отсутствует", missing), ("Отличается", changed), ("Лишний файл", extra)):
        for name in sorted(names):
            print(f"{label}: Example/Chat/CTChat/{name}")

    if not (missing or extra or changed):
        print(f"Копии SDK совпадают ({len(source)} Swift-файлов).")
        return 0
    if args.check:
        return 1
    if extra:
        print("Синхронизация отменена: разберите лишние файлы вручную; автоматического удаления нет.", file=sys.stderr)
        return 1

    # Проверяем все назначения до первой записи, включая staged-изменения и удаления.
    for name in sorted(missing | changed):
        target = DESTINATION / name
        relative = str(target.relative_to(ROOT))
        # После git rm файл уже отсутствует в индексе, но его удаление ещё не закоммичено.
        index = subprocess.run(["git", "diff", "--cached", "--quiet", "--", relative], cwd=ROOT)
        if index.returncode != 0:
            raise ValueError(f"Синхронизация отменена: незакоммиченные изменения в {relative}")
        tracked = subprocess.run(
            ["git", "ls-files", "-v", "-z", "--error-unmatch", "--", relative], cwd=ROOT,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        if tracked.returncode not in (0, 1):
            raise ValueError(f"Не удалось проверить состояние Git: {relative}")
        if tracked.returncode == 0:
            # -v: S означает skip-worktree, строчная метка — assume-unchanged (включая s).
            tags = [entry[:1] for entry in tracked.stdout.split(b"\0") if entry]
            if any(tag == b"S" or tag.islower() for tag in tags):
                raise ValueError(
                    f"Синхронизация отменена: {relative} помечен assume-unchanged "
                    "или skip-worktree; файл и флаги оставлены без изменений"
                )
            working_tree = subprocess.run(["git", "diff", "--quiet", "--", relative], cwd=ROOT)
            if working_tree.returncode != 0:
                raise ValueError(f"Синхронизация отменена: незакоммиченные изменения в {relative}")
        elif target.exists():
            raise ValueError(f"Синхронизация отменена: незакоммиченный файл {relative}")

    for name in sorted(missing | changed):
        target = DESTINATION / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source[name], target)
        print(f"Скопирован: {target.relative_to(ROOT)}")
    print("Копии синхронизированы. Для новых файлов проверьте Compile Sources в target Chat.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"Ошибка: {error}", file=sys.stderr)
        sys.exit(1)
