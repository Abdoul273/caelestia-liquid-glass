#!/usr/bin/env python3
"""Shared, locked task store for AuraTask and the Caelestia quick panel."""

import fcntl
import json
import os
import sys
import tempfile
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

STORE = Path(os.environ.get("AURATASK_TASKS_FILE", Path.home() / ".local/share/auratask/tasks.json"))
LEGACY = Path(os.environ.get("CAELESTIA_TASKS_FILE", Path.home() / ".local/share/caelestia/tasks.json"))


def quick_task(title, task_id=None, created=None):
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    return {
        "id": task_id or f"quick_{uuid.uuid4().hex}",
        "title": title.strip(),
        "description": "",
        "priority": "medium",
        "status": "todo",
        "category": "Personnel & Santé",
        "dueDate": None,
        "estimatedMinutes": 30,
        "timeSpentMinutes": 0,
        "completed": False,
        "completedAt": None,
        "createdAt": created or now,
        "updatedAt": now,
        "tags": [],
        "subtasks": [],
        "smartReminders": [],
    }


def initial_state():
    tasks = []
    if LEGACY.exists():
        try:
            old = json.loads(LEGACY.read_text(encoding="utf-8"))
            for item in old if isinstance(old, list) else []:
                if not isinstance(item, dict) or not str(item.get("text", "")).strip():
                    continue
                created = item.get("created", time.time() * 1000)
                task = quick_task(
                    str(item["text"]),
                    f"caelestia_{item.get('id', uuid.uuid4().hex)}",
                    time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(created / 1000)),
                )
                task["completed"] = bool(item.get("done"))
                task["status"] = "done" if task["completed"] else "todo"
                if task["completed"]:
                    task["completedAt"] = time.strftime(
                        "%Y-%m-%dT%H:%M:%SZ", time.gmtime(item.get("doneAt", created) / 1000)
                    )
                tasks.append(task)
        except (OSError, ValueError, TypeError):
            pass
    return {"revision": 0, "tasks": tasks}


def write_state(state):
    STORE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=STORE.parent, prefix=".tasks-", delete=False
    ) as tmp:
        name = tmp.name
        json.dump(state, tmp, ensure_ascii=False, indent=2)
        tmp.flush()
        os.fsync(tmp.fileno())
    os.chmod(name, 0o600)
    os.replace(name, STORE)


@contextmanager
def locked_state():
    STORE.parent.mkdir(parents=True, exist_ok=True)
    with (STORE.parent / ".tasks.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if STORE.exists():
            state = json.loads(STORE.read_text(encoding="utf-8"))
        else:
            state = initial_state()
            write_state(state)
        yield state


def payload_arg(index=2):
    raw = sys.stdin.read() if len(sys.argv) <= index or sys.argv[index] == "-" else sys.argv[index]
    return json.loads(raw)


def run(state):
    command = sys.argv[1]
    tasks = state["tasks"]
    changed = False
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    if command == "read":
        return False
    if command == "import":
        existing = {task["id"] for task in tasks}
        for task in payload_arg():
            if isinstance(task, dict) and isinstance(task.get("id"), str) and task["id"] not in existing:
                tasks.append(task)
                existing.add(task["id"])
                changed = True
    elif command == "apply":
        for operation in payload_arg():
            kind = operation.get("type")
            if kind == "upsert":
                task = operation.get("task")
                if not isinstance(task, dict) or not isinstance(task.get("id"), str):
                    continue
                index = next((i for i, old in enumerate(tasks) if old["id"] == task["id"]), -1)
                if index >= 0:
                    if tasks[index] != task:
                        tasks[index] = task
                        changed = True
                else:
                    tasks.insert(0, task)
                    changed = True
            elif kind == "delete":
                before = len(tasks)
                tasks[:] = [task for task in tasks if task["id"] != operation.get("id")]
                changed |= len(tasks) != before
            elif kind == "order":
                order = operation.get("ids", [])
                rank = {task_id: i for i, task_id in enumerate(order)}
                tasks.sort(key=lambda task: rank.get(task["id"], len(rank)))
                changed = True
    elif command == "add":
        title = sys.argv[2].strip()
        if title:
            tasks.insert(0, quick_task(title))
            changed = True
    elif command in {"toggle", "edit", "remove", "clear-done"}:
        task_id = sys.argv[2] if len(sys.argv) > 2 else ""
        task = next((item for item in tasks if item["id"] == task_id), None)
        if command == "clear-done":
            before = len(tasks)
            tasks[:] = [item for item in tasks if not item.get("completed")]
            changed = len(tasks) != before
        elif task and command == "remove":
            tasks.remove(task)
            changed = True
        elif task and command == "toggle":
            task["completed"] = not task.get("completed", False)
            task["status"] = "done" if task["completed"] else "todo"
            task["completedAt"] = now if task["completed"] else None
            task["updatedAt"] = now
            changed = True
        elif task and command == "edit":
            title = sys.argv[3].strip() if len(sys.argv) > 3 else ""
            if title and title != task["title"]:
                task["title"] = title
                task["updatedAt"] = now
                changed = True
    else:
        raise ValueError(f"Unknown command: {command}")

    if changed:
        state["revision"] += 1
        write_state(state)
    return changed


if __name__ == "__main__":
    try:
        with locked_state() as current:
            run(current)
            print(json.dumps(current, ensure_ascii=False))
    except (OSError, ValueError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
