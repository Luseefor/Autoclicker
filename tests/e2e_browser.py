#!/usr/bin/env python3
"""E2E: drive Automater's Engine against a live Playwright Chromium window.

Run:  .venv/bin/python tests/e2e_browser.py

Requires Accessibility permission for the hosting terminal (cursor-warping
foreground cases). Background cases never move your pointer.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

FIXTURE = ROOT / "tests" / "fixtures" / "click_target.html"
TITLE_MARK = "AUTOMATER-E2E"
# Playwright's Chromium shows up as this owner (titles need Screen Recording).
OWNER_MARK = "chrome for testing"
WIN_POS = (140, 140)
WIN_SIZE = "--window-size=1000,760"

PASS: list[str] = []
FAIL: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    (PASS if cond else FAIL).append(name + (f" — {detail}" if detail and not cond else ""))
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"  [{detail}]" if detail else ""))


def main() -> int:
    from app import permissions as perms

    if not perms.is_accessibility_trusted():
        print("Accessibility permission required for the E2E harness.")
        return 2

    from playwright.sync_api import sync_playwright

    from app.engine import Engine
    from app import windows as winmod

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=False,
            args=[
                f"--window-position={WIN_POS[0]},{WIN_POS[1]}",
                WIN_SIZE,
            ],
        )
        page = browser.new_page(viewport=None)
        page.goto(FIXTURE.as_uri())
        page.wait_for_timeout(400)

        wins = [
            w for w in winmod.list_windows()
            if OWNER_MARK in (w.app_name or "").lower()
        ]
        if not wins:
            print("Could not discover the Chromium window — is it on screen?")
            browser.close()
            return 2
        target = max(wins, key=lambda w: w.area)
        print(f"target window: pid={target.pid} {int(target.width)}x{int(target.height)}")
        # Playwright windows open behind the terminal — bring forward for fg cases.
        winmod.activate_app(pid=target.pid)
        time.sleep(0.5)

        def ev():
            return page.evaluate("window.__events")

        def center(sel):
            return page.evaluate(f"window.__center('{sel}')")

        # ---- calibrate client→screen with one real foreground click ----
        engine = Engine()
        probe = center("#bar")
        engine.start_clicker(
            interval_ms=200,
            mode="fixed",
            fixed_x=int(probe["x"]),
            fixed_y=int(probe["y"]),
            repeat_count=1,
        )
        deadline = time.time() + 5
        while time.time() < deadline and len(ev()["clicks"]) == 0:
            time.sleep(0.05)
        engine.stop(silent=True)
        got = ev()["clicks"]
        if not got:
            print("Calibration click did not land — aborting.")
            browser.close()
            return 2
        dx = probe["x"] - (probe["screenX"] + got[-1]["x"])
        dy = probe["y"] - (probe["screenY"] + got[-1]["y"])

        def scr(client_pt):
            return (int(client_pt["x"] + dx), int(client_pt["y"] + dy))

        single = scr(center("#single"))
        double = scr(center("#double"))
        bar = scr(center("#bar"))
        kb = scr(center("#kb"))
        page.evaluate("window.__reset()")
        print(f"calibration offset dx={dx} dy={dy}")

        def wait_for(pred, timeout=12.0):
            end = time.time() + timeout
            while time.time() < end:
                if pred():
                    return True
                time.sleep(0.08)
            return False

        def run_case(name, **kwargs):
            page.evaluate("window.__reset()")
            eng = Engine()
            eng.start_clicker(**kwargs)
            rep = kwargs.get("repeat_count", 0) or 1
            ok = wait_for(lambda: len(ev()["clicks"]) >= rep * 3, timeout=max(6, rep * 1.6))
            time.sleep(0.35)
            eng.stop(silent=True)
            return ev(), ok

        # ---- CASE 1: foreground single ×5 ----
        e, _ = run_case(
            "fg_single",
            interval_ms=750, mode="fixed", fixed_x=single[0], fixed_y=single[1],
            repeat_count=5,
        )
        n = len(e["clicks"])
        dbl = sum(1 for c in e["clicks"] if c["detail"] >= 2)
        check("fg single ×5 lands 5 clicks", n == 5, f"got {n}")
        check("fg singles stay single (no promotion)", dbl == 0, f"{dbl} promoted")

        # ---- CASE 2: foreground double ×3 ----
        e, _ = run_case(
            "fg_double",
            interval_ms=1100, mode="fixed", fixed_x=double[0], fixed_y=double[1],
            click_kind="double", repeat_count=3,
        )
        check("fg double ×3 → 3 native dblclicks", e["dblclicks"] == 3,
              f"got {e['dblclicks']}")

        # ---- CASE 3: background single ×4 (pointer untouched) ----
        before_xy = None
        try:
            from app.engine import _cursor_pos
            before_xy = _cursor_pos()
        except Exception:
            pass
        e, _ = run_case(
            "bg_single",
            interval_ms=750, mode="fixed", fixed_x=single[0], fixed_y=single[1],
            repeat_count=4, app_name=OWNER_MARK and "Google Chrome for Testing",
            background_to_app=True,
        )
        n = len(e["clicks"])
        check("bg single ×4 delivered", n == 4, f"got {n}")
        try:
            from app.engine import _cursor_pos
            after_xy = _cursor_pos()
            check("bg single leaves cursor still",
                  abs(after_xy[0] - before_xy[0]) < 2 and abs(after_xy[1] - before_xy[1]) < 2,
                  f"moved {before_xy}→{after_xy}")
        except Exception:
            pass

        # ---- CASE 4: background double ×2 ----
        e, _ = run_case(
            "bg_double",
            interval_ms=1200, mode="fixed", fixed_x=double[0], fixed_y=double[1],
            click_kind="double", repeat_count=2,
            app_name="Google Chrome for Testing", background_to_app=True,
        )
        check("bg double ×2 → 2 dblclicks", e["dblclicks"] == 2, f"got {e['dblclicks']}")
        n = len(e["clicks"])
        check("bg double fires no duplicate stream", n == 4, f"got {n} raw clicks")

        # ---- CASE 5: multipoint alternating (background, pid-tagged points) ----
        points = [
            {"x": single[0], "y": single[1], "coord_space": "screen", "pid": target.pid},
            {"x": double[0], "y": double[1], "coord_space": "screen", "pid": target.pid},
        ]
        page.evaluate("window.__reset()")
        eng = Engine()
        eng.start_clicker(
            interval_ms=800, mode="multipoint", multipoints=points,
            repeat_count=6, background_to_app=True, window_title=TITLE_MARK,
        )
        ok = wait_for(lambda: len(ev()["clicks"]) >= 6, timeout=14)
        time.sleep(0.35)
        eng.stop(silent=True)
        e = ev()
        zones = [c["zone"] for c in e["clicks"]]
        r1 = zones.count("single")
        r2 = zones.count("double")
        check("multipoint delivers all 6", len(zones) == 6, f"zones={zones}")
        check("multipoint alternates evenly", abs(r1 - r2) <= 1, f"single={r1} double={r2}")

        # ---- CASE 6: background key into focused input ----
        eng = Engine()
        eng.start_clicker(interval_ms=150, mode="fixed",
                          fixed_x=kb[0], fixed_y=kb[1], repeat_count=1)
        wait_for(lambda: len(ev()["clicks"]) >= 1)
        eng.stop(silent=True)

        from app.models import Macro, MacroStep, StepType

        macro = Macro(
            name="e2e-key",
            steps=[
                MacroStep(type=StepType.KEY, key="a", delay_ms=120),
                MacroStep(type=StepType.KEY, key="b", delay_ms=120),
            ],
            loop_count=1,
        )
        eng = Engine()
        eng.play_macro(macro, background_to_app=True)
        # macro targets nothing explicitly; bg key path needs a pid — fall back
        # to global pynput here, which is fine: we assert text arrived.
        ok = wait_for(lambda: "".join(ev()["keys"]).find("ab") >= 0, timeout=8)
        eng.stop(silent=True)
        check("key steps type into focused input", ok,
              f"keys={ev()['keys']}")

        browser.close()

    print("\n===== SUMMARY =====")
    for p in PASS:
        print(f"  PASS  {p}")
    for f in FAIL:
        print(f"  FAIL  {f}")
    print(f"{len(PASS)} passed, {len(FAIL)} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
