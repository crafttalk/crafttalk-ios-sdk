"""Замеры этапов CI с сохранением результата даже при ошибке или отмене."""

from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import threading
import time


class Stage:
    def __init__(self, artifacts, name):
        self.path = Path(artifacts) / "timings.json"
        self.name = name
        self.status = 0
        self.stopped = threading.Event()

    def save(self):
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.records, indent=2) + "\n")
        temporary.replace(self.path)

    def __enter__(self):
        self.started = time.monotonic()
        self.records = json.loads(self.path.read_text()) if self.path.exists() else []
        self.record = {"stage": self.name, "startedAt": datetime.now(timezone.utc).isoformat(), "status": "running"}
        self.records.append(self.record)
        self.save()
        print(f"[CI] Начало: {self.name}", flush=True)
        self.thread = threading.Thread(target=self.heartbeat, daemon=True)
        self.thread.start()
        return self

    def heartbeat(self):
        while not self.stopped.wait(30):
            print(f"[CI] Выполняется: {self.name}, {time.monotonic() - self.started:.0f} с", flush=True)

    def __exit__(self, kind, error, traceback):
        self.stopped.set()
        self.thread.join()
        elapsed = round(time.monotonic() - self.started, 3)
        self.record.update(durationSeconds=elapsed, status="failed" if kind or self.status else "passed")
        if error:
            self.record["error"] = type(error).__name__
        self.record["exitCode"] = (self.status if not kind else
                                   130 if isinstance(error, KeyboardInterrupt) else getattr(error, "returncode", 1))
        self.save()
        print(f"[CI] Конец: {self.name}, {elapsed:.1f} с, {self.record['status']}", flush=True)


if __name__ == "__main__":
    with Stage(sys.argv[1], sys.argv[2]) as stage:
        stage.status = subprocess.call(sys.argv[3:])
    sys.exit(stage.status)
