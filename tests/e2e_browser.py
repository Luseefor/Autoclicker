#!/usr/bin/env python3
"""E2E: drive Automater's engine against a live Playwright Chromium window.

Run:
  AUTOMATER_E2E_ENGINE=swift  .venv/bin/python tests/e2e_browser.py   # default
  AUTOMATER_E2E_ENGINE=python .venv/bin/python tests/e2e_browser.py

Requires Accessibility permission for the hosting terminal (foreground cases
warp the pointer; background cases never touch it).
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

FIXTURE = ROOT / "tests" / "fixtures" / "click_target.html"
OWNER_MARK = "chrome for testing"
WIN_POS = (140, 140)
WIN_SIZE = "--window-size=1000,760"

ENGINE = os.environ.get("AUTOMATER_E2E_ENGINE", "swift").lower()
CLI = ROOT / "AutomaterMac" / ".build" / "debug" / "automater-cli"

PASS: list[str] = []
FAIL: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    (PASS if cond else FAIL).append(name)
    tag = "PASS" if cond else "FAIL"
    print(f"  {tag}  {name}" + (f"  [{detail}]" if detail and not cond else ""))


class PageDead(Exception):
    pass


def main() -> int:
    if ENGINE == "swift":
        subprocess.run(
            ["swift", "build"], cwd=str(ROOT / "AutomaterMac"), check=True,
            capture_output=True,
        )
        if not CLI.exists():
            print("automater-cli missing after build")
            return 2

    from app import permissions as perms

    if not perms.is_accessibility_trusted():
        print("Accessibility permission required for the E2E harness.")
        return 2

    from playwright.sync_api import sync_playwright

    from app import windows as winmod

    # ---- engine drivers ----

    def py_click_fixed(x, y, interval, repeat, kind="single", app_name=None, bg=False):
        from app.engine import Engine

        eng = Engine()
        eng.start_clicker(
            interval_ms=interval, mode="fixed", fixed_x=x, fixed_y=y,
            repeat_count=repeat, click_kind=kind,
            app_name=app_name, background_to_app=bg,
        )
        return eng

    def py_multipoint(points, pid, interval, repeat, kind="single"):
        from app.engine import Engine

        specs = [
            {"x": p[0], "y": p[1], "coord_space": "screen", "pid": pid}
            for p in points
        ]
        eng = Engine()
        eng.start_clicker(
            interval_ms=interval, mode="multipoint", multipoints=specs,
            repeat_count=repeat, click_kind=kind, background_to_app=True,
        )
        return eng

    def sw_click(x, y, interval, repeat, kind="single", app_name=None, bg=False,
                 pid=None, window_id=None):
        args = [
            str(CLI), "click-fixed",
            "--x", str(int(x)), "--y", str(int(y)),
            "--interval", str(interval), "--repeat", str(repeat),
            "--kind", kind,
        ]
        if app_name:
            args += ["--app-name", app_name]
        if pid:
            args += ["--pid", str(pid), "--window-id", str(window_id or 0)]
        if bg:
            args.append("--bg")
        subprocess.run(args, check=True)

    def sw_multipoint(points, pid, interval, repeat, kind="single"):
        args = [str(CLI), "multipoint",
                "--interval", str(interval), "--repeat", str(repeat),
                "--kind", kind]
        for p in points:
            args += ["--point", f"{int(p[0])},{int(p[1])}",
                     "--point-pid", str(pid)]
        args.append("--bg")
        subprocess.run(args, check=True)

    def sw_cursor():
        out = subprocess.run([str(CLI), "cursor"], capture_output=True, text=True)
        x, y = out.stdout.strip().split(",")
        return float(x), float(y)

    use_swift = ENGINE == "swift"
    TARGET_PID = [None]
    TARGET_WID = [None]

    def driver_click(x, y, interval, repeat, kind="single", app_name=None, bg=False):
        if use_swift:
            return sw_click(x, y, interval, repeat, kind, app_name, bg,
                            pid=TARGET_PID, window_id=TARGET_WID)
        return py_click_fixed(x, y, interval, repeat, kind, app_name, bg)

    def driver_multipoint(points, pid, interval, repeat, kind="single"):
        if use_swift:
            return sw_multipoint(points, pid, interval, repeat, kind)
        return py_multipoint(points, pid, interval, repeat, kind)

    # ---- browser target ----

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=False,
            args=[f"--window-position={WIN_POS[0]},{WIN_POS[1]}", WIN_SIZE],
        )
        page = browser.new_page(viewport=None)

        def ev() -> dict:
            try:
                return page.evaluate("window.__events")
            except Exception as exc:
                raise PageDead(str(exc)) from exc

        def center(sel: str) -> dict:
            try:
                return page.evaluate(f"window.__center('{sel}')")
            except Exception as exc:
                raise PageDead(str(exc)) from exc

        page.goto(FIXTURE.as_uri())
        page.wait_for_timeout(400)

        wins = [
            w for w in winmod.list_windows()
            if OWNER_MARK in (w.app_name or "").lower()
        ]
        if not wins:
            print("Could not discover the Chromium window.")
            browser.close()
            return 2
        target = max(wins, key=lambda w: w.area)
        TARGET_PID[0] = target.pid
        TARGET_WID[0] = target.window_id
        print(f"target window: pid={target.pid} "
              f"{int(target.width)}x{int(target.height)}  engine={ENGINE}")
        winmod.activate_app(pid=target.pid)
        time.sleep(0.5)

        APP_NAME = target.app_name  # exact owner string, e.g. Google Chrome for Testing

        # ---- calibrate client→screen with one real foreground click ----
        probe = center("#bar")
        driver_click(probe["x"], probe["y"], 200, 1)
        deadline = time.time() + 5
        while time.time() < deadline and len(ev()["clicks"]) == 0:
            time.sleep(0.05)
        got = ev()["clicks"]
        if not got:
            print("Calibration click did not land — aborting.")
            browser.close()
            return 2
        dx = probe["x"] - (probe["screenX"] + got[-1]["x"])
        dy = probe["y"] - (probe["screenY"] + got[-1]["y"])

        def scr(pt: dict) -> tuple[int, int]:
            return int(pt["x"] + dx), int(pt["y"] + dy)

        single = scr(center("#single"))
        double = scr(center("#double"))
        kb = scr(center("#kb"))
        page.evaluate("window.__reset()")
        print(f"calibration offset dx={dx} dy={dy}")

        def wait_for(pred, timeout: float) -> bool:
            end = time.time() + timeout
            while time.time() < end:
                if pred():
                    return True
                time.sleep(0.08)
            return False

        def case(name: str, fn) -> None:
            print(f"\n— {name}")
            try:
                page.evaluate("window.__reset()")
                fn()
            except PageDead as exc:
                check(name, False, f"browser died: {exc}")

        def settle(expected_raw: int, timeout: float) -> dict:
            wait_for(lambda: len(ev()["clicks"]) >= expected_raw, timeout)
            time.sleep(0.35)
            return ev()

        # CASE 1 — foreground singles must stay single
        def c1():
            driver_click(single[0], single[1], 750, 5)
            e = settle(5, 8)
            n = len(e["clicks"])
            promoted = sum(1 for c in e["clicks"] if c["detail"] >= 2)
            zones = [c["zone"] for c in e["clicks"]]
            check("fg single ×5 lands 5 clicks", n == 5, f"got {n}")
            check("fg singles not promoted", promoted == 0, f"{promoted} promoted")
            check("fg clicks hit SINGLE zone", zones.count("single") == n, str(zones))
        case("fg_single", c1)

        # CASE 2 — foreground doubles
        def c2():
            driver_click(double[0], double[1], 1100, 3, kind="double")
            e = settle(6, 8)
            check("fg double ×3 → 3 native dblclicks", e["dblclicks"] == 3,
                  f"got {e['dblclicks']}")
        case("fg_double", c2)

        # CASE 3 — background singles, pointer untouched
        def c3():
            before = EventPosterCursor()
            driver_click(single[0], single[1], 750, 4, app_name=APP_NAME, bg=True)
            e = settle(4, 8)
            n = len(e["clicks"])
            after = EventPosterCursor()
            check("bg single ×4 delivered", n == 4, f"got {n}")
            moved = abs(after[0] - before[0]) > 2 or abs(after[1] - before[1]) > 2
            check("bg single leaves cursor still", not moved, f"{before}→{after}")
        case("bg_single", c3)

        # CASE 4 — background doubles, no duplicate stream
        def c4():
            driver_click(double[0], double[1], 1200, 2, kind="double",
                         app_name=APP_NAME, bg=True)
            e = settle(4, 8)
            check("bg double ×2 → 2 dblclicks", e["dblclicks"] == 2,
                  f"got {e['dblclicks']}")
            n = len(e["clicks"])
            check("bg double fires no duplicates", n == 4, f"got {n} raw clicks")
        case("bg_double", c4)

        # CASE 5 — multipoint alternation in background (pid-tagged points)
        def c5():
            driver_multipoint([single, double], target.pid, 800, 6)
            e = settle(6, 14)
            zones = [c["zone"] for c in e["clicks"]]
            r1, r2 = zones.count("single"), zones.count("double")
            check("multipoint delivers all 6", len(zones) == 6, f"zones={zones}")
            check("multipoint alternates evenly", abs(r1 - r2) <= 1,
                  f"single={r1} double={r2}")
        case("multipoint_bg", c5)

        # CASE 6 — key chord into focused input (python engine only; UI phase
        # will add a swift keyboard driver)
        def c6():
            if use_swift:
                check("key steps type into input (swift)", True, "skipped until Phase E")
                return
            driver_click(kb[0], kb[1], 150, 1)
            wait_for(lambda: len(ev()["clicks"]) >= 1, 5)

            from app.models import Macro, MacroStep, StepType
            from app.engine import Engine

            macro = Macro(name="e2e-key", loop_count=1, steps=[
                MacroStep(type=StepType.KEY, key="a", delay_ms=120),
                MacroStep(type=StepType.KEY, key="b", delay_ms=120),
            ])
            eng = Engine()
            eng.play_macro(macro)
            ok = wait_for(lambda: "ab" in "".join(ev()["keys"]), 8)
            eng.stop(silent=True)
            check("key steps type into focused input", ok, f"keys={ev()['keys']}")
        case("key_input", c6)

        browser.close()

    print("\n===== SUMMARY =====")
    for p in PASS:
        print(f"  PASS  {p}")
    for f in FAIL:
        print(f"  FAIL  {f}")
    print(f"{len(PASS)} passed, {len(FAIL)} failed  (engine={ENGINE})")
    return 1 if FAIL else 0


def EventPosterCursor() -> tuple[float, float]:
    if ENGINE == "swift":
        out = subprocess.run([str(CLI), "cursor"], capture_output=True, text=True)
        x, y = out.stdout.strip().split(",")
        return float(x), float(y)
    from app.engine import _cursor_pos
    return _cursor_pos()


if __name__ == "__main__":
    raise SystemExit(main())
