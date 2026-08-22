"""Main Automater application window."""

from __future__ import annotations

import os

from PySide6.QtCore import QSize, Qt, QTimer, Signal, Slot
from PySide6.QtGui import QAction, QCloseEvent, QKeySequence
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QDoubleSpinBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QRadioButton,
    QSpinBox,
    QSplitter,
    QStatusBar,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from app import icons as app_icons
from app import permissions as perms
from app import storage
from app import windows as winmod
from app.engine import Engine
from app.hotkeys import HotkeyManager
from app.models import Macro, MacroStep, StepType
from app.recorder import Recorder
from app.styles import APP_STYLE
from app.widgets import HotkeyEditor, hotkey_bar


class Bridge(QWidget):
    status = Signal(str)
    steps = Signal(object)
    point_picked = Signal(int, int)
    pick_done = Signal()


class StepEditorDialog(QDialog):
    def __init__(self, parent: QWidget | None = None, step: MacroStep | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("Edit step")
        self.setMinimumWidth(400)
        layout = QFormLayout(self)

        self.type_box = QComboBox()
        for t in StepType:
            self.type_box.addItem(t.value, t.value)
        self.coord_space = QComboBox()
        self.coord_space.addItems(["screen", "window"])
        self.x = QSpinBox()
        self.x.setRange(-20000, 20000)
        self.y = QSpinBox()
        self.y.setRange(-20000, 20000)
        self.local_x = QDoubleSpinBox()
        self.local_x.setRange(-20000, 20000)
        self.local_y = QDoubleSpinBox()
        self.local_y.setRange(-20000, 20000)
        self.end_x = QSpinBox()
        self.end_x.setRange(-20000, 20000)
        self.end_y = QSpinBox()
        self.end_y.setRange(-20000, 20000)
        self.button = QComboBox()
        self.button.addItems(["left", "right", "middle"])
        self.click_kind = QComboBox()
        self.click_kind.addItems(["single", "double", "triple"])
        self.key = QLineEdit()
        self.text = QLineEdit()
        self.delay = QSpinBox()
        self.delay.setRange(0, 600_000)
        self.delay.setSuffix(" ms")
        self.hold = QSpinBox()
        self.hold.setRange(0, 600_000)
        self.hold.setSuffix(" ms")
        self.clicks = QSpinBox()
        self.clicks.setRange(1, 20)
        self.dx = QSpinBox()
        self.dx.setRange(-100, 100)
        self.dy = QSpinBox()
        self.dy.setRange(-100, 100)
        self.app_bundle = QLineEdit()
        self.app_name = QLineEdit()
        self.window_title = QLineEdit()
        self.timeout = QSpinBox()
        self.timeout.setRange(0, 600_000)
        self.timeout.setSuffix(" ms")
        self.timeout.setValue(10_000)

        layout.addRow("Type", self.type_box)
        layout.addRow("Coord space", self.coord_space)
        layout.addRow("X", self.x)
        layout.addRow("Y", self.y)
        layout.addRow("Local X", self.local_x)
        layout.addRow("Local Y", self.local_y)
        layout.addRow("End X", self.end_x)
        layout.addRow("End Y", self.end_y)
        layout.addRow("Button", self.button)
        layout.addRow("Click kind", self.click_kind)
        layout.addRow("Key", self.key)
        layout.addRow("Text", self.text)
        layout.addRow("Delay", self.delay)
        layout.addRow("Hold", self.hold)
        layout.addRow("Clicks", self.clicks)
        layout.addRow("Scroll dx", self.dx)
        layout.addRow("Scroll dy", self.dy)
        layout.addRow("App bundle id", self.app_bundle)
        layout.addRow("App name", self.app_name)
        layout.addRow("Window title", self.window_title)
        layout.addRow("Timeout", self.timeout)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addRow(buttons)

        if step:
            idx = self.type_box.findData(step.type)
            if idx >= 0:
                self.type_box.setCurrentIndex(idx)
            self.coord_space.setCurrentText(step.coord_space or "screen")
            if step.x is not None:
                self.x.setValue(int(step.x))
            if step.y is not None:
                self.y.setValue(int(step.y))
            if step.local_x is not None:
                self.local_x.setValue(step.local_x)
            if step.local_y is not None:
                self.local_y.setValue(step.local_y)
            if step.end_x is not None:
                self.end_x.setValue(int(step.end_x))
            if step.end_y is not None:
                self.end_y.setValue(int(step.end_y))
            if step.button:
                self.button.setCurrentText(step.button)
            self.click_kind.setCurrentText(step.click_kind or "single")
            self.key.setText(step.key or "")
            self.text.setText(step.text or "")
            self.delay.setValue(step.delay_ms)
            self.hold.setValue(step.hold_ms)
            self.clicks.setValue(step.clicks)
            if step.dx is not None:
                self.dx.setValue(step.dx)
            if step.dy is not None:
                self.dy.setValue(step.dy)
            self.app_bundle.setText(step.app_bundle_id or "")
            self.app_name.setText(step.app_name or "")
            self.window_title.setText(step.window_title or "")
            self.timeout.setValue(step.timeout_ms)

    def result_step(self) -> MacroStep:
        return MacroStep(
            type=self.type_box.currentData(),
            coord_space=self.coord_space.currentText(),
            x=self.x.value(),
            y=self.y.value(),
            local_x=self.local_x.value(),
            local_y=self.local_y.value(),
            end_x=self.end_x.value(),
            end_y=self.end_y.value(),
            button=self.button.currentText(),
            click_kind=self.click_kind.currentText(),
            key=self.key.text().strip() or None,
            text=self.text.text() or None,
            delay_ms=self.delay.value(),
            hold_ms=self.hold.value(),
            clicks=self.clicks.value(),
            dx=self.dx.value(),
            dy=self.dy.value(),
            app_bundle_id=self.app_bundle.text().strip() or None,
            app_name=self.app_name.text().strip() or None,
            window_title=self.window_title.text().strip() or None,
            timeout_ms=self.timeout.value(),
        )


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Automater")
        self.resize(1100, 760)
        self.setMinimumSize(900, 640)
        self.setStyleSheet(APP_STYLE)

        self.settings = storage.load_settings()
        self.bridge = Bridge()
        self.engine = Engine(on_status=lambda m: self.bridge.status.emit(m))
        self.recorder = Recorder(
            on_status=lambda m: self.bridge.status.emit(m),
            on_steps=lambda s: self.bridge.steps.emit(s),
        )
        self.hotkeys = HotkeyManager()
        self._draft_steps: list[MacroStep] = []
        self._selected_macro: Macro | None = None
        self._multipoints: list[dict] = list(self.settings.get("multipoints") or [])
        self._apps_cache: list = []
        self._picking = False
        self._pick_mouse = None
        self._pick_keys = None

        self.bridge.status.connect(self._on_status)
        self.bridge.steps.connect(self._on_recorded_steps)
        self.bridge.point_picked.connect(self._on_point_picked)
        self.bridge.pick_done.connect(self._stop_picking)

        self._build_menu()
        self._build_ui()
        self._refresh_macro_list()
        self._apply_settings_to_form()
        self._refresh_apps()
        self._refresh_permissions()
        self._install_hotkeys()

        self._poll = QTimer(self)
        self._poll.timeout.connect(self._on_poll)
        self._poll.start(300)

        self.statusBar().showMessage("Ready — Stop pauses only. Quit via File or ⌘Q.")

    # ----- chrome -----

    def _build_menu(self) -> None:
        file_menu = self.menuBar().addMenu("&File")
        quit_act = QAction("Quit", self)
        quit_act.setShortcut(QKeySequence.StandardKey.Quit)
        quit_act.triggered.connect(self.close)
        file_menu.addAction(quit_act)

        help_menu = self.menuBar().addMenu("&Help")
        access = QAction("Permissions help", self)
        access.triggered.connect(self._show_accessibility_help)
        help_menu.addAction(access)

    def _build_ui(self) -> None:
        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(22, 18, 22, 18)
        outer.setSpacing(16)

        header = QHBoxLayout()
        header.setSpacing(10)
        brand = QLabel("Automater")
        brand.setObjectName("brand")
        header.addWidget(brand)
        header.addStretch(1)
        self.status_pill = QLabel("Idle")
        self.status_pill.setObjectName("statusPill")
        header.addWidget(self.status_pill)
        self.stop_btn = QPushButton("Stop")
        self.stop_btn.setObjectName("danger")
        self.stop_btn.clicked.connect(self.stop_all)
        header.addWidget(self.stop_btn)
        outer.addLayout(header)

        self.perm_banner = QLabel("")
        self.perm_banner.setObjectName("permBanner")
        self.perm_banner.setWordWrap(True)
        self.perm_banner.hide()
        outer.addWidget(self.perm_banner)

        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_clicker_tab(), "Clicker")
        self.tabs.addTab(self._build_macros_tab(), "Macros")
        self.tabs.addTab(self._build_record_tab(), "Record")
        self.tabs.addTab(self._build_target_tab(), "Target")
        self.tabs.addTab(self._build_settings_tab(), "Settings")
        outer.addWidget(self.tabs, 1)
        self.setStatusBar(QStatusBar())
        self.bg_click.toggled.connect(self.target_bg_click.setChecked)
        self.target_bg_click.toggled.connect(self.bg_click.setChecked)

    def _build_clicker_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(18)

        columns = QHBoxLayout()
        columns.setSpacing(18)

        form_box = QGroupBox("Clicker")
        form = QVBoxLayout(form_box)
        form.setSpacing(16)
        form.setContentsMargins(12, 14, 12, 12)

        interval_row = QHBoxLayout()
        interval_row.setSpacing(8)
        lab_i = QLabel("Interval")
        lab_i.setMinimumWidth(90)
        interval_row.addWidget(lab_i)
        self.int_h = QSpinBox()
        self.int_h.setRange(0, 24)
        self.int_h.setSuffix(" h")
        self.int_h.setMinimumWidth(78)
        self.int_m = QSpinBox()
        self.int_m.setRange(0, 59)
        self.int_m.setSuffix(" m")
        self.int_m.setMinimumWidth(78)
        self.int_s = QSpinBox()
        self.int_s.setRange(0, 59)
        self.int_s.setSuffix(" s")
        self.int_s.setMinimumWidth(78)
        self.int_ms = QSpinBox()
        self.int_ms.setRange(0, 999)
        self.int_ms.setSuffix(" ms")
        self.int_ms.setMinimumWidth(90)
        self.int_ms.setValue(100)
        for w in (self.int_h, self.int_m, self.int_s, self.int_ms):
            interval_row.addWidget(w)
        interval_row.addStretch(1)
        form.addLayout(interval_row)

        btn_row = QHBoxLayout()
        btn_row.setSpacing(12)
        lab_b = QLabel("Button")
        lab_b.setMinimumWidth(90)
        btn_row.addWidget(lab_b)
        self.button_combo = QComboBox()
        self.button_combo.addItems(["left", "right", "middle"])
        self.button_combo.setMinimumWidth(140)
        btn_row.addWidget(self.button_combo)
        btn_row.addSpacing(16)
        btn_row.addWidget(QLabel("Click type"))
        self.click_kind = QComboBox()
        self.click_kind.addItems(["single", "double", "triple"])
        self.click_kind.setMinimumWidth(140)
        btn_row.addWidget(self.click_kind)
        btn_row.addStretch(1)
        form.addLayout(btn_row)

        mode_row = QHBoxLayout()
        mode_row.setSpacing(16)
        lab_m = QLabel("Mode")
        lab_m.setMinimumWidth(90)
        mode_row.addWidget(lab_m)
        self.mode_current = QRadioButton("Current cursor")
        self.mode_fixed = QRadioButton("Fixed position")
        self.mode_multi = QRadioButton("Multi-point list")
        self.mode_multi.setChecked(True)
        mode_row.addWidget(self.mode_current)
        mode_row.addWidget(self.mode_fixed)
        mode_row.addWidget(self.mode_multi)
        mode_row.addStretch(1)
        form.addLayout(mode_row)

        pos_row = QHBoxLayout()
        pos_row.setSpacing(8)
        lab_p = QLabel("Fixed X / Y")
        lab_p.setMinimumWidth(90)
        pos_row.addWidget(lab_p)
        self.fixed_x = QSpinBox()
        self.fixed_x.setRange(-20000, 20000)
        self.fixed_x.setMinimumWidth(100)
        self.fixed_y = QSpinBox()
        self.fixed_y.setRange(-20000, 20000)
        self.fixed_y.setMinimumWidth(100)
        grab = QPushButton("Click screen to set")
        grab.setMinimumWidth(150)
        grab.clicked.connect(self._pick_fixed_point)
        pos_row.addWidget(self.fixed_x)
        pos_row.addWidget(self.fixed_y)
        pos_row.addWidget(grab)
        pos_row.addStretch(1)
        form.addLayout(pos_row)

        rep_row = QHBoxLayout()
        rep_row.setSpacing(12)
        lab_r = QLabel("Repeat")
        lab_r.setMinimumWidth(90)
        rep_row.addWidget(lab_r)
        self.repeat_spin = QSpinBox()
        self.repeat_spin.setRange(0, 1_000_000)
        self.repeat_spin.setSpecialValueText("Infinite")
        self.repeat_spin.setMinimumWidth(110)
        rep_row.addWidget(self.repeat_spin)
        rep_row.addSpacing(16)
        rep_row.addWidget(QLabel("Jitter ±"))
        self.jitter_spin = QSpinBox()
        self.jitter_spin.setRange(0, 5000)
        self.jitter_spin.setSuffix(" ms")
        self.jitter_spin.setMinimumWidth(110)
        rep_row.addWidget(self.jitter_spin)
        rep_row.addStretch(1)
        form.addLayout(rep_row)

        self.bg_click = QCheckBox("Click target app in background (keep game on top)")
        self.bg_click.setChecked(False)
        self.bg_click.setToolTip(
            "Send clicks straight to the target app without bringing it forward.\n"
            "Your pointer stays exactly where it is."
        )
        form.addWidget(self.bg_click)
        form.addStretch(1)

        mp_box = QGroupBox("Multi-points")
        mp_l = QVBoxLayout(mp_box)
        mp_l.setSpacing(12)
        mp_l.setContentsMargins(10, 10, 10, 10)
        tip = QLabel(
            "Click Add points, then click each spot on the app. "
            "Esc or Done when finished."
        )
        tip.setObjectName("subtitle")
        tip.setWordWrap(True)
        mp_l.addWidget(tip)
        self.point_list = QListWidget()
        self.point_list.setMinimumHeight(180)
        mp_l.addWidget(self.point_list, 1)
        mp_btns = QHBoxLayout()
        mp_btns.setSpacing(8)
        self.pick_btn = QPushButton("Add points")
        self.pick_btn.setObjectName("primary")
        self.pick_btn.setMinimumWidth(120)
        self.pick_btn.clicked.connect(self.toggle_pick_points)
        rem_pt = QPushButton("Remove")
        rem_pt.clicked.connect(self._remove_multipoint)
        clear_pt = QPushButton("Clear")
        clear_pt.clicked.connect(self._clear_multipoints)
        mp_btns.addWidget(self.pick_btn)
        mp_btns.addWidget(rem_pt)
        mp_btns.addWidget(clear_pt)
        mp_btns.addStretch(1)
        mp_l.addLayout(mp_btns)

        columns.addWidget(form_box, 3)
        columns.addWidget(mp_box, 2)
        layout.addLayout(columns, 1)

        actions = QHBoxLayout()
        actions.setSpacing(14)
        self.clicker_toggle = QPushButton("Start clicking")
        self.clicker_toggle.setObjectName("primary")
        self.clicker_toggle.setMinimumWidth(160)
        self.clicker_toggle.setMinimumHeight(38)
        self.clicker_toggle.clicked.connect(self.toggle_clicker)
        actions.addWidget(self.clicker_toggle)
        actions.addWidget(
            hotkey_bar(
                [
                    (["Ctrl", "Opt", "A"], "start / stop"),
                    (["Ctrl", "Opt", "S"], "stop all"),
                    (["Esc"], "end picking"),
                ]
            ),
            1,
        )
        layout.addLayout(actions)
        return page

    def _build_macros_tab(self) -> QWidget:
        page = QWidget()
        layout = QHBoxLayout(page)
        splitter = QSplitter()

        left = QWidget()
        left_l = QVBoxLayout(left)
        left_l.setContentsMargins(0, 0, 0, 0)
        left_l.addWidget(QLabel("Saved macros"))
        self.macro_list = QListWidget()
        self.macro_list.currentItemChanged.connect(self._on_macro_selected)
        left_l.addWidget(self.macro_list, 1)
        left_btns = QHBoxLayout()
        new_btn = QPushButton("New")
        new_btn.clicked.connect(self._new_macro)
        del_btn = QPushButton("Delete")
        del_btn.setObjectName("danger")
        del_btn.clicked.connect(self._delete_macro)
        imp_btn = QPushButton("Import")
        imp_btn.clicked.connect(self._import_macro)
        exp_btn = QPushButton("Export")
        exp_btn.clicked.connect(self._export_macro)
        for b in (new_btn, del_btn, imp_btn, exp_btn):
            left_btns.addWidget(b)
        left_l.addLayout(left_btns)

        right = QWidget()
        right_l = QVBoxLayout(right)
        right_l.setContentsMargins(0, 0, 0, 0)

        name_row = QHBoxLayout()
        self.macro_name = QLineEdit()
        self.macro_name.setPlaceholderText("Macro name")
        name_row.addWidget(self.macro_name, 1)
        self.loop_spin = QSpinBox()
        self.loop_spin.setRange(0, 10_000)
        self.loop_spin.setSpecialValueText("∞")
        name_row.addWidget(QLabel("Loops"))
        name_row.addWidget(self.loop_spin)
        self.speed_spin = QDoubleSpinBox()
        self.speed_spin.setRange(0.1, 10.0)
        self.speed_spin.setSingleStep(0.1)
        self.speed_spin.setValue(1.0)
        name_row.addWidget(QLabel("Speed"))
        name_row.addWidget(self.speed_spin)
        right_l.addLayout(name_row)

        self.macro_activate = QCheckBox("Activate target app before play")
        self.macro_activate.setChecked(True)
        right_l.addWidget(self.macro_activate)

        self.step_list = QListWidget()
        self.step_list.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        right_l.addWidget(self.step_list, 1)

        step_btns = QHBoxLayout()
        for label, slot in (
            ("Add step", self._add_step),
            ("Edit", self._edit_step),
            ("Remove", self._remove_step),
            ("↑", lambda: self._move_step(-1)),
            ("↓", lambda: self._move_step(1)),
        ):
            b = QPushButton(label)
            b.clicked.connect(slot)
            step_btns.addWidget(b)
        right_l.addLayout(step_btns)

        quick = QHBoxLayout()
        for label, slot in (
            ("Add key", self._quick_add_key),
            ("Type text", self._quick_add_type),
            ("Delay", self._quick_add_delay),
            ("Click here", self._quick_add_click),
            ("Activate app", self._quick_add_activate),
            ("Wait window", self._quick_add_wait_window),
        ):
            b = QPushButton(label)
            b.clicked.connect(slot)
            quick.addWidget(b)
        right_l.addLayout(quick)

        play_row = QHBoxLayout()
        save_btn = QPushButton("Save macro")
        save_btn.setObjectName("primary")
        save_btn.clicked.connect(self._save_current_macro)
        play_btn = QPushButton("Play")
        play_btn.setObjectName("primary")
        play_btn.clicked.connect(self._play_selected_macro)
        play_row.addWidget(save_btn)
        play_row.addWidget(play_btn)
        right_l.addLayout(play_row)

        splitter.addWidget(left)
        splitter.addWidget(right)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 2)
        layout.addWidget(splitter)
        return page

    def _build_record_tab(self) -> QWidget:
        page = QWidget()
        layout = QHBoxLayout(page)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(16)

        left = QVBoxLayout()
        left.setSpacing(14)

        target_card = QFrame()
        target_card.setObjectName("softCard")
        tc = QHBoxLayout(target_card)
        tc.setContentsMargins(14, 12, 14, 12)
        tc.setSpacing(12)
        self.rec_target_icon = QLabel()
        self.rec_target_icon.setObjectName("appIconBadge")
        self.rec_target_icon.setFixedSize(44, 44)
        self.rec_target_icon.setAlignment(Qt.AlignmentFlag.AlignCenter)
        tc.addWidget(self.rec_target_icon)
        ttxt = QVBoxLayout()
        ttxt.setSpacing(2)
        tcap = QLabel("Recording target")
        tcap.setObjectName("sectionCaption")
        self.rec_target_name = QLabel("No target selected")
        self.rec_target_name.setObjectName("cardTitle")
        self.rec_target_detail = QLabel("Pick an app on the Target tab")
        self.rec_target_detail.setObjectName("subtitle")
        self.rec_target_detail.setWordWrap(True)
        ttxt.addWidget(tcap)
        ttxt.addWidget(self.rec_target_name)
        ttxt.addWidget(self.rec_target_detail)
        tc.addLayout(ttxt, 1)
        go_target = QPushButton("Choose…")
        go_target.clicked.connect(lambda: self.tabs.setCurrentIndex(3))
        tc.addWidget(go_target)
        left.addWidget(target_card)

        opts = QGroupBox("What to capture")
        opts_l = QVBoxLayout(opts)
        opts_l.setSpacing(10)
        self.rec_clicks = QCheckBox("Mouse clicks / drag / hold")
        self.rec_clicks.setChecked(True)
        self.rec_keys = QCheckBox("Keyboard")
        self.rec_keys.setChecked(True)
        self.rec_moves = QCheckBox("Mouse moves")
        self.rec_moves.setChecked(False)
        self.rec_scroll = QCheckBox("Scroll")
        self.rec_scroll.setChecked(True)
        self.rec_window_rel = QCheckBox("Store coords relative to target window")
        self.rec_window_rel.setChecked(True)
        for w in (self.rec_clicks, self.rec_keys, self.rec_moves, self.rec_scroll, self.rec_window_rel):
            opts_l.addWidget(w)
        left.addWidget(opts)

        actions = QGroupBox("Session")
        act = QVBoxLayout(actions)
        act.setSpacing(10)
        self.record_btn = QPushButton("Start recording")
        self.record_btn.setObjectName("primary")
        self.record_btn.setMinimumHeight(40)
        self.record_btn.clicked.connect(self.toggle_recording)
        act.addWidget(self.record_btn)
        act.addWidget(hotkey_bar([(["Ctrl", "Opt", "R"], "toggle")]))
        row = QHBoxLayout()
        clear_btn = QPushButton("Clear")
        clear_btn.clicked.connect(self._clear_recording)
        save_rec = QPushButton("Save as macro…")
        save_rec.clicked.connect(self._save_recording_as_macro)
        play_rec = QPushButton("Play")
        play_rec.clicked.connect(self._play_recording)
        for b in (clear_btn, save_rec, play_rec):
            row.addWidget(b)
        act.addLayout(row)
        tip = QLabel("Clicks on Automater are ignored.")
        tip.setObjectName("subtitle")
        tip.setWordWrap(True)
        act.addWidget(tip)
        left.addWidget(actions)
        left.addStretch(1)

        right = QVBoxLayout()
        right.setSpacing(8)
        head = QHBoxLayout()
        steps_lab = QLabel("Recorded steps")
        steps_lab.setObjectName("cardTitle")
        head.addWidget(steps_lab)
        head.addStretch(1)
        self.rec_step_count = QLabel("0 steps")
        self.rec_step_count.setObjectName("subtitle")
        head.addWidget(self.rec_step_count)
        right.addLayout(head)

        self.record_list = QListWidget()
        self.record_list.setObjectName("stepList")
        self.record_list.setAlternatingRowColors(True)
        right.addWidget(self.record_list, 1)

        layout.addLayout(left, 2)
        layout.addLayout(right, 3)
        return page

    def _build_target_tab(self) -> QWidget:
        page = QWidget()
        layout = QHBoxLayout(page)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(16)

        # —— Apps ——
        apps_col = QVBoxLayout()
        apps_col.setSpacing(8)
        apps_head = QHBoxLayout()
        apps_title = QLabel("Running apps")
        apps_title.setObjectName("cardTitle")
        apps_head.addWidget(apps_title)
        apps_head.addStretch(1)
        self.app_count_lab = QLabel("")
        self.app_count_lab.setObjectName("subtitle")
        apps_head.addWidget(self.app_count_lab)
        apps_col.addLayout(apps_head)

        self.app_filter = QLineEdit()
        self.app_filter.setPlaceholderText("Filter by name…")
        self.app_filter.setClearButtonEnabled(True)
        self.app_filter.textChanged.connect(self._filter_app_list)
        apps_col.addWidget(self.app_filter)

        self.app_list = QListWidget()
        self.app_list.setObjectName("appList")
        self.app_list.setIconSize(QSize(32, 32))
        self.app_list.setSpacing(2)
        self.app_list.currentItemChanged.connect(self._on_app_selected)
        apps_col.addWidget(self.app_list, 1)

        app_btns = QHBoxLayout()
        refresh = QPushButton("Refresh")
        refresh.clicked.connect(self._refresh_apps)
        front = QPushButton("Use frontmost")
        front.clicked.connect(self._use_frontmost)
        app_btns.addWidget(refresh)
        app_btns.addWidget(front)
        apps_col.addLayout(app_btns)

        # —— Windows ——
        win_col = QVBoxLayout()
        win_col.setSpacing(8)
        win_title = QLabel("Windows")
        win_title.setObjectName("cardTitle")
        win_col.addWidget(win_title)
        win_sub = QLabel("Largest first — pick the content window")
        win_sub.setObjectName("subtitle")
        win_col.addWidget(win_sub)
        self.window_list = QListWidget()
        self.window_list.setObjectName("appList")
        self.window_list.setIconSize(QSize(24, 24))
        self.window_list.setSpacing(2)
        self.window_list.currentItemChanged.connect(self._on_window_selected)
        win_col.addWidget(self.window_list, 1)

        # —— Target + permissions ——
        right = QVBoxLayout()
        right.setSpacing(14)

        target_box = QGroupBox("Current target")
        tf = QVBoxLayout(target_box)
        tf.setSpacing(12)
        hero = QHBoxLayout()
        hero.setSpacing(14)
        self.target_icon = QLabel()
        self.target_icon.setObjectName("appIconBadge")
        self.target_icon.setFixedSize(56, 56)
        self.target_icon.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hero.addWidget(self.target_icon)
        hero_txt = QVBoxLayout()
        hero_txt.setSpacing(4)
        self.target_app_label = QLabel("—")
        self.target_app_label.setObjectName("cardTitle")
        self.target_bundle_label = QLabel("—")
        self.target_bundle_label.setObjectName("subtitle")
        self.target_bundle_label.setWordWrap(True)
        self.target_window_label = QLabel("—")
        self.target_window_label.setWordWrap(True)
        hero_txt.addWidget(self.target_app_label)
        hero_txt.addWidget(self.target_bundle_label)
        hero_txt.addWidget(self.target_window_label)
        hero.addLayout(hero_txt, 1)
        tf.addLayout(hero)

        self.coord_label = QLabel("Cursor —")
        self.coord_label.setObjectName("subtitle")
        tf.addWidget(self.coord_label)

        opts = QLabel("When this target is used")
        opts.setObjectName("sectionCaption")
        tf.addWidget(opts)

        self.activate_target = QCheckBox("Bring target app forward before play")
        self.activate_target.setChecked(False)
        tf.addWidget(self.activate_target)

        self.target_bg_click = QCheckBox("Also click it in the background")
        self.target_bg_click.setChecked(False)
        self.target_bg_click.setToolTip(
            "Clicks are delivered to this app without moving your pointer."
        )
        tf.addWidget(self.target_bg_click)

        self.rec_use_target = QCheckBox("Use this target when recording")
        self.rec_use_target.setChecked(True)
        tf.addWidget(self.rec_use_target)

        actions = QHBoxLayout()
        done_t = QPushButton("Done")
        done_t.setObjectName("primary")
        done_t.clicked.connect(self._done_target)
        clear_t = QPushButton("Clear")
        clear_t.clicked.connect(self._clear_target)
        actions.addWidget(done_t, 1)
        actions.addWidget(clear_t)
        tf.addLayout(actions)
        right.addWidget(target_box)

        perm_box = QGroupBox("Permissions")
        pf = QVBoxLayout(perm_box)
        pf.setSpacing(10)

        self.ax_row = QWidget()
        axl = QHBoxLayout(self.ax_row)
        axl.setContentsMargins(0, 0, 0, 0)
        axl.setSpacing(8)
        ax_name = QLabel("Accessibility")
        ax_name.setObjectName("permName")
        self.ax_status = QLabel("…")
        self.ax_status.setObjectName("permBadge")
        axl.addWidget(ax_name)
        axl.addStretch(1)
        axl.addWidget(self.ax_status)
        pf.addWidget(self.ax_row)

        self.im_row = QWidget()
        iml = QHBoxLayout(self.im_row)
        iml.setContentsMargins(0, 0, 0, 0)
        iml.setSpacing(8)
        im_name = QLabel("Input Monitoring")
        im_name.setObjectName("permName")
        self.im_status = QLabel("…")
        self.im_status.setObjectName("permBadge")
        iml.addWidget(im_name)
        iml.addStretch(1)
        iml.addWidget(self.im_status)
        pf.addWidget(self.im_row)

        self.im_note = QLabel("")
        self.im_note.setObjectName("subtitle")
        self.im_note.setWordWrap(True)
        pf.addWidget(self.im_note)

        self.perm_grant_btn = QPushButton("Grant Accessibility")
        self.perm_grant_btn.setObjectName("primary")
        self.perm_grant_btn.clicked.connect(self._request_accessibility)
        pf.addWidget(self.perm_grant_btn)

        links = QHBoxLayout()
        links.setSpacing(8)
        self.perm_open_ax = QPushButton("Accessibility")
        self.perm_open_ax.setObjectName("linkBtn")
        self.perm_open_ax.clicked.connect(perms.open_accessibility_settings)
        self.perm_open_im = QPushButton("Input Monitoring")
        self.perm_open_im.setObjectName("linkBtn")
        self.perm_open_im.clicked.connect(perms.open_input_monitoring_settings)
        recheck = QPushButton("Recheck")
        recheck.setObjectName("linkBtn")
        recheck.clicked.connect(self._refresh_permissions)
        links.addWidget(self.perm_open_ax)
        links.addWidget(self.perm_open_im)
        links.addStretch(1)
        links.addWidget(recheck)
        pf.addLayout(links)
        right.addWidget(perm_box)
        right.addStretch(1)

        layout.addLayout(apps_col, 2)
        layout.addLayout(win_col, 2)
        layout.addLayout(right, 2)
        return page
    def _build_settings_tab(self) -> QWidget:
        page = QWidget()
        layout = QFormLayout(page)
        layout.setSpacing(12)

        self.hk_toggle = HotkeyEditor("<ctrl>+<alt>+a")
        self.hk_record = HotkeyEditor("<ctrl>+<alt>+r")
        self.hk_stop = HotkeyEditor("<ctrl>+<alt>+s")
        for ed in (self.hk_toggle, self.hk_record, self.hk_stop):
            ed.set_listen_hooks(on_start=self.hotkeys.stop, on_stop=self._install_hotkeys)

        self.failsafe_check = QCheckBox("Fail-safe pauses instead of crashing")
        self.failsafe_check.setChecked(True)

        save = QPushButton("Save settings")
        save.setObjectName("primary")
        save.clicked.connect(self._save_settings)

        layout.addRow("Toggle clicker / play", self.hk_toggle)
        layout.addRow("Toggle record", self.hk_record)
        layout.addRow("Stop all", self.hk_stop)
        layout.addRow(self.failsafe_check)
        layout.addRow(save)

        note = QLabel(
            "Click Change, then press the shortcut you want. "
            "Grant Accessibility if hotkeys fail."
        )
        note.setObjectName("subtitle")
        note.setWordWrap(True)
        layout.addRow(note)
        return page

    # ----- permissions / target -----

    def _set_perm_badge(self, label: QLabel, text: str, kind: str) -> None:
        label.setText(text)
        label.setProperty("kind", kind)
        label.style().unpolish(label)
        label.style().polish(label)

    def _refresh_permissions(self) -> None:
        st = perms.get_status()
        if st.accessibility:
            self._set_perm_badge(self.ax_status, "On", "ok")
            self.perm_grant_btn.hide()
            self.perm_banner.hide()
        else:
            self._set_perm_badge(self.ax_status, "Needed", "need")
            self.perm_grant_btn.show()
            self.perm_banner.setText(
                "Accessibility is off — record, play, and hotkeys are paused until you grant it."
            )
            self.perm_banner.show()

        if st.input_monitoring is True:
            self._set_perm_badge(self.im_status, "On", "ok")
            self.im_note.hide()
        elif st.input_monitoring is False:
            self._set_perm_badge(self.im_status, "Needed", "need")
            self.im_note.setText(st.input_monitoring_note)
            self.im_note.show()
        else:
            self._set_perm_badge(self.im_status, "Check Settings", "maybe")
            self.im_note.setText(st.input_monitoring_note)
            self.im_note.show()

    def _request_accessibility(self) -> None:
        perms.request_accessibility()
        self._refresh_permissions()

    def _trusted_or_warn(self) -> bool:
        if perms.is_accessibility_trusted():
            return True
        self._refresh_permissions()
        QMessageBox.warning(
            self,
            "Permissions required",
            "Grant Accessibility permission first (Target & Permissions tab).",
        )
        return False

    def _refresh_apps(self) -> None:
        self._apps_cache = winmod.list_running_apps()
        self._filter_app_list()
        n = len(self._apps_cache)
        if hasattr(self, "app_count_lab"):
            self.app_count_lab.setText(f"{n} apps")
        self.statusBar().showMessage(f"{n} apps")

    def _filter_app_list(self) -> None:
        if not hasattr(self, "app_list"):
            return
        needle = ""
        if hasattr(self, "app_filter"):
            needle = self.app_filter.text().strip().lower()
        selected_key = None
        cur = self.app_list.currentItem()
        if cur:
            app = cur.data(Qt.ItemDataRole.UserRole)
            if app:
                selected_key = app.bundle_id or f"pid:{app.pid}"

        self.app_list.blockSignals(True)
        self.app_list.clear()
        self.window_list.clear()
        restore_row = -1
        for app in getattr(self, "_apps_cache", []):
            if needle and needle not in app.name.lower() and needle not in (app.bundle_id or "").lower():
                continue
            item = QListWidgetItem(app.name)
            tip = app.bundle_id or f"pid {app.pid}"
            item.setToolTip(tip)
            item.setData(Qt.ItemDataRole.UserRole, app)
            item.setIcon(app_icons.icon_for(pid=app.pid, bundle_id=app.bundle_id or None, size=32))
            item.setSizeHint(QSize(0, 40))
            self.app_list.addItem(item)
            key = app.bundle_id or f"pid:{app.pid}"
            if selected_key and key == selected_key:
                restore_row = self.app_list.count() - 1
        self.app_list.blockSignals(False)
        if restore_row >= 0:
            self.app_list.setCurrentRow(restore_row)

    def _on_app_selected(self, current: QListWidgetItem | None, _prev) -> None:
        self.window_list.clear()
        if not current:
            return
        app = current.data(Qt.ItemDataRole.UserRole)
        icon = app_icons.icon_for(pid=app.pid, bundle_id=app.bundle_id or None, size=24)
        # Prefer pid match; fall back to bundle if needed
        wins = winmod.list_windows(pid=app.pid)
        if not wins and app.bundle_id:
            wins = winmod.list_windows(bundle_id=app.bundle_id)
        for w in wins:
            title = w.title.strip() or "(Untitled)"
            label = f"{title}\n{int(w.width)}×{int(w.height)}"
            item = QListWidgetItem(label)
            item.setToolTip(f"id={w.window_id}  {w.bundle_id}")
            item.setData(Qt.ItemDataRole.UserRole, w)
            item.setIcon(icon)
            item.setSizeHint(QSize(0, 44))
            self.window_list.addItem(item)
        # Auto-select largest window and set target app even without a window pick
        if wins:
            self.window_list.setCurrentRow(0)
            w0 = wins[0]
            self._set_target(w0.app_name, w0.bundle_id, w0.title, pid=w0.pid)
        else:
            self._set_target(app.name, app.bundle_id, "", pid=app.pid)

    def _on_window_selected(self, current: QListWidgetItem | None, _prev) -> None:
        if not current:
            return
        w = current.data(Qt.ItemDataRole.UserRole)
        self._set_target(w.app_name, w.bundle_id, w.title, pid=w.pid)

    def _use_frontmost(self) -> None:
        w = winmod.frontmost_window()
        if not w:
            self.statusBar().showMessage("No frontmost window")
            return
        self._set_target(w.app_name, w.bundle_id, w.title, pid=w.pid)
        self._refresh_apps()

    def _set_target(
        self,
        name: str,
        bundle_id: str,
        title: str,
        pid: int | None = None,
    ) -> None:
        self.settings["target_app_name"] = name
        self.settings["target_bundle_id"] = bundle_id or ""
        self.settings["target_window_title"] = title
        if pid is not None:
            self.settings["target_pid"] = int(pid)
        self.target_app_label.setText(name or "—")
        self.target_bundle_label.setText(bundle_id or "—")
        self.target_window_label.setText(title or "No window selected")
        self._update_target_icons(pid=pid, bundle_id=bundle_id or None, name=name)

    def _update_target_icons(
        self,
        pid: int | None = None,
        bundle_id: str | None = None,
        name: str = "",
    ) -> None:
        bid = bundle_id or str(self.settings.get("target_bundle_id") or "") or None
        if pid is None:
            raw = self.settings.get("target_pid")
            pid = int(raw) if raw else None
        display_name = name or str(self.settings.get("target_app_name") or "")
        window = str(self.settings.get("target_window_title") or "")

        pm = app_icons.pixmap_for(pid=pid, bundle_id=bid, size=56)
        if hasattr(self, "target_icon"):
            if pm.isNull():
                self.target_icon.clear()
                self.target_icon.setText("?")
            else:
                self.target_icon.setText("")
                self.target_icon.setPixmap(pm)

        if hasattr(self, "rec_target_icon"):
            rpm = app_icons.pixmap_for(pid=pid, bundle_id=bid, size=44)
            if rpm.isNull():
                self.rec_target_icon.clear()
                self.rec_target_icon.setText("?")
            else:
                self.rec_target_icon.setText("")
                self.rec_target_icon.setPixmap(rpm)
            if display_name:
                self.rec_target_name.setText(display_name)
                self.rec_target_detail.setText(window or bid or "App selected")
            else:
                self.rec_target_name.setText("No target selected")
                self.rec_target_detail.setText("Pick an app on the Target tab")

    def _clear_target(self) -> None:
        self.settings.pop("target_pid", None)
        self._set_target("", "", "")

    def _done_target(self) -> None:
        name, bid, title = self._current_target()
        if not (name or bid):
            QMessageBox.information(self, "Target", "Pick an app from the list first.")
            return
        self._persist_clicker_settings()
        self.tabs.setCurrentIndex(0)
        extra = title.strip() if title else ""
        msg = f"Target set: {name}" + (f" — {extra}" if extra else "")
        self.statusBar().showMessage(msg)


    def _current_target(self) -> tuple[str, str, str]:
        return (
            str(self.settings.get("target_app_name") or ""),
            str(self.settings.get("target_bundle_id") or ""),
            str(self.settings.get("target_window_title") or ""),
        )

    def _on_poll(self) -> None:
        self._sync_status_pill()
        try:
            from app.engine import _cursor_pos

            x, y = _cursor_pos()
            name, bid, title = self._current_target()
            local = "—"
            if bid or name:
                w = winmod.find_window(
                    bundle_id=bid or None, app_name=name or None, window_title=title or None
                )
                if w and winmod.point_in_window(x, y, w):
                    lx, ly = winmod.screen_to_local(x, y, w)
                    local = f"({lx:.0f}, {ly:.0f})"
            self.coord_label.setText(f"Cursor ({int(x)}, {int(y)})  ·  local {local}")
        except Exception:
            pass
    # ----- hotkeys / status -----

    def _install_hotkeys(self) -> None:
        if not perms.is_accessibility_trusted():
            self.hotkeys.stop()
            return
        self.hotkeys.set_bindings(
            {
                self.settings.get("hotkey_toggle", "<ctrl>+<alt>+a"): self._hotkey_toggle,
                self.settings.get("hotkey_record", "<ctrl>+<alt>+r"): self.toggle_recording,
                self.settings.get("hotkey_stop", "<ctrl>+<alt>+s"): self.stop_all,
            }
        )

    def _hotkey_toggle(self) -> None:
        if self.engine.running:
            self.stop_all()
            return
        if self.tabs.currentIndex() == 1 and self._selected_macro:
            self._play_selected_macro()
        else:
            self.toggle_clicker()

    @Slot(str)
    def _on_status(self, message: str) -> None:
        self.statusBar().showMessage(message)
        self._sync_status_pill()

    @Slot(object)
    def _on_recorded_steps(self, steps: object) -> None:
        self._draft_steps = list(steps)  # type: ignore[arg-type]
        self.record_list.clear()
        for step in self._draft_steps:
            self.record_list.addItem(step.label())
        if hasattr(self, "rec_step_count"):
            n = len(self._draft_steps)
            self.rec_step_count.setText(f"{n} step" if n == 1 else f"{n} steps")

    def _sync_status_pill(self) -> None:
        if self._picking:
            text, active, rec = "Picking points", False, False
            self.status_pill.setProperty("picking", True)
        elif self.recorder.recording:
            text, active, rec = "Recording", False, True
            self.status_pill.setProperty("picking", False)
            self.record_btn.setText("Stop recording")
        elif self.engine.mode == "clicker":
            text, active, rec = "Clicker ON", True, False
            self.status_pill.setProperty("picking", False)
            self.clicker_toggle.setText("Stop clicking")
        elif self.engine.mode == "macro":
            text, active, rec = "Playing macro", True, False
            self.status_pill.setProperty("picking", False)
            self.clicker_toggle.setText("Start clicking")
        else:
            text, active, rec = "Idle", False, False
            self.status_pill.setProperty("picking", False)
            self.clicker_toggle.setText("Start clicking")
            if hasattr(self, "record_btn"):
                self.record_btn.setText("Start recording")
        self.status_pill.setText(text)
        self.status_pill.setProperty("active", active)
        self.status_pill.setProperty("recording", rec)
        self.status_pill.style().unpolish(self.status_pill)
        self.status_pill.style().polish(self.status_pill)

    # ----- clicker -----

    def _grab_cursor(self) -> None:
        from app.engine import _cursor_pos

        x, y = _cursor_pos()
        self.fixed_x.setValue(int(x))
        self.fixed_y.setValue(int(y))
        # Grab always stores screen coords for reliable fixed clicking
        self.settings["fixed_coord_space"] = "screen"
        self.settings["fixed_local_x"] = 0.0
        self.settings["fixed_local_y"] = 0.0
        self.settings["fixed_window_id"] = None
        name, bid, title = self._current_target()
        if bid or name:
            w = winmod.find_window(
                bundle_id=bid or None, app_name=name or None, window_title=title or None
            )
            if w and winmod.point_in_window(x, y, w):
                lx, ly = winmod.screen_to_local(x, y, w)
                self.settings["fixed_coord_space"] = "window"
                self.settings["fixed_local_x"] = float(lx)
                self.settings["fixed_local_y"] = float(ly)
                self.settings["fixed_window_id"] = int(w.window_id)
                self.statusBar().showMessage(
                    f"Grabbed local ({lx:.0f}, {ly:.0f}) in {w.app_name}"
                )
            else:
                self.statusBar().showMessage(f"Grabbed screen ({int(x)}, {int(y)})")
        else:
            self.statusBar().showMessage(f"Grabbed screen ({int(x)}, {int(y)})")
        self.mode_fixed.setChecked(True)
    def _refresh_point_list(self) -> None:
        self.point_list.clear()
        for i, p in enumerate(self._multipoints):
            if p.get("coord_space") == "window":
                text = (
                    f"{i+1}. {p.get('app_name')}  "
                    f"({p.get('local_x'):.0f}, {p.get('local_y'):.0f})"
                )
            else:
                text = f"{i+1}. screen ({p.get('x')}, {p.get('y')})"
            self.point_list.addItem(text)

    def _point_from_screen(self, x: int, y: int) -> dict:
        """Build a multipoint dict, binding to the app under the click when possible."""
        point: dict = {"x": int(x), "y": int(y), "coord_space": "screen"}
        w = winmod.window_at_point(x, y)
        # Prefer explicit Target tab selection if the click lands in that app
        name, bid, title = self._current_target()
        if bid or name:
            preferred = winmod.find_window(
                bundle_id=bid or None, app_name=name or None, window_title=title or None
            )
            if preferred and winmod.point_in_window(x, y, preferred):
                w = preferred
        if w and w.pid not in winmod.our_app_pids():
            lx, ly = winmod.screen_to_local(x, y, w)
            point.update(
                {
                    "coord_space": "window",
                    "local_x": float(lx),
                    "local_y": float(ly),
                    "app_bundle_id": w.bundle_id,
                    "app_name": w.app_name,
                    "window_title": w.title,
                    "pid": w.pid,
                    "window_id": w.window_id,
                }
            )
            # Remember as current target
            self._set_target(w.app_name, w.bundle_id, w.title, pid=w.pid)
        return point

    def toggle_pick_points(self) -> None:
        if self._picking:
            self._stop_picking()
            return
        if not self._trusted_or_warn():
            return
        self._pick_kind = "multi"
        self._start_picking()

    def _pick_fixed_point(self) -> None:
        if self._picking:
            self._stop_picking()
            return
        if not self._trusted_or_warn():
            return
        self._pick_kind = "fixed"
        self._start_picking()

    def _start_picking(self) -> None:
        from pynput import mouse

        from app.mac_keys import KeyMonitor

        self.engine.stop(silent=True)
        self._picking = True
        if hasattr(self, "pick_btn"):
            self.pick_btn.setText("Done picking (Esc)")
        self.status_pill.setText("Click screen…")
        self.status_pill.setProperty("picking", True)
        self.status_pill.style().unpolish(self.status_pill)
        self.status_pill.style().polish(self.status_pill)
        self.statusBar().showMessage(
            "Click the app where you want points. Esc or Done when finished."
        )
        if self._pick_kind == "multi":
            self.mode_multi.setChecked(True)
        else:
            self.mode_fixed.setChecked(True)

        our_pids = winmod.our_app_pids()

        def on_click(x, y, button, pressed):
            if not pressed or not self._picking:
                return
            hit = winmod.window_at_point(x, y)
            if hit and hit.pid in our_pids:
                return
            # Also ignore if click is inside this window's frame
            from PySide6.QtCore import QPoint

            if self.frameGeometry().contains(QPoint(int(x), int(y))):
                return
            self.bridge.point_picked.emit(int(x), int(y))

        def on_key(name: str, _event) -> None:
            if name == "esc" and self._picking:
                self.bridge.pick_done.emit()

        self._pick_mouse = mouse.Listener(on_click=on_click)
        self._pick_keys = KeyMonitor(on_down=on_key)
        self._pick_mouse.start()
        self._pick_keys.start()

    @Slot()
    def _stop_picking(self) -> None:
        self._picking = False
        if self._pick_mouse:
            try:
                self._pick_mouse.stop()
            except Exception:
                pass
            self._pick_mouse = None
        if self._pick_keys:
            try:
                self._pick_keys.stop()
            except Exception:
                pass
            self._pick_keys = None
        if hasattr(self, "pick_btn"):
            self.pick_btn.setText("Add points")
        self.status_pill.setProperty("picking", False)
        self.status_pill.style().unpolish(self.status_pill)
        self.status_pill.style().polish(self.status_pill)
        self._sync_status_pill()
        self.statusBar().showMessage(f"{len(self._multipoints)} points ready")

    @Slot(int, int)
    def _on_point_picked(self, x: int, y: int) -> None:
        point = self._point_from_screen(x, y)
        if getattr(self, "_pick_kind", "multi") == "fixed":
            self.fixed_x.setValue(int(point["x"]))
            self.fixed_y.setValue(int(point["y"]))
            if point.get("coord_space") == "window":
                self.settings["fixed_coord_space"] = "window"
                self.settings["fixed_local_x"] = float(point["local_x"])
                self.settings["fixed_local_y"] = float(point["local_y"])
                self.settings["fixed_window_id"] = point.get("window_id")
                self.statusBar().showMessage(
                    f"Fixed point in {point.get('app_name')} "
                    f"({point['local_x']:.0f}, {point['local_y']:.0f})"
                )
            else:
                self.settings["fixed_coord_space"] = "screen"
                self.statusBar().showMessage(f"Fixed screen ({x}, {y})")
            self.mode_fixed.setChecked(True)
            self._stop_picking()
            return

        self._multipoints.append(point)
        self._refresh_point_list()
        self.mode_multi.setChecked(True)
        label = (
            f"{point.get('app_name')} ({point.get('local_x'):.0f}, {point.get('local_y'):.0f})"
            if point.get("coord_space") == "window"
            else f"screen ({x}, {y})"
        )
        self.statusBar().showMessage(f"Added {label} — keep clicking or Esc")

    def _remove_multipoint(self) -> None:
        row = self.point_list.currentRow()
        if 0 <= row < len(self._multipoints):
            self._multipoints.pop(row)
            self._refresh_point_list()

    def _clear_multipoints(self) -> None:
        self._multipoints.clear()
        self._refresh_point_list()

    def toggle_clicker(self) -> None:
        if self.engine.mode == "clicker":
            self.engine.stop()
            return
        if self._picking:
            self._stop_picking()
        if not self._trusted_or_warn():
            return
        self._persist_clicker_settings()
        name, bid, title = self._current_target()
        mode = "current"
        if self.mode_fixed.isChecked():
            mode = "fixed"
        elif self.mode_multi.isChecked():
            mode = "multipoint"
            if not self._multipoints:
                QMessageBox.information(
                    self,
                    "Clicker",
                    "Add points first: Click screen to add points, then click the app.",
                )
                return
        interval = storage.interval_to_ms(
            self.int_h.value(), self.int_m.value(), self.int_s.value(), self.int_ms.value()
        )
        coord_space = "screen"
        local_x = 0.0
        local_y = 0.0
        window_id = None
        if mode == "fixed":
            coord_space = str(self.settings.get("fixed_coord_space", "screen"))
            local_x = float(self.settings.get("fixed_local_x", 0))
            local_y = float(self.settings.get("fixed_local_y", 0))
            raw_wid = self.settings.get("fixed_window_id")
            window_id = int(raw_wid) if raw_wid else None
        bg = self.bg_click.isChecked() and mode in {"fixed", "multipoint"}
        self.engine.start_clicker(
            interval_ms=interval,
            button=self.button_combo.currentText(),
            mode=mode,
            fixed_x=self.fixed_x.value(),
            fixed_y=self.fixed_y.value(),
            failsafe_pauses=bool(self.settings.get("failsafe_pauses", True)),
            click_kind=self.click_kind.currentText(),
            repeat_count=self.repeat_spin.value(),
            jitter_ms=self.jitter_spin.value(),
            coord_space=coord_space,
            local_x=local_x,
            local_y=local_y,
            app_bundle_id=bid or None,
            app_name=name or None,
            window_title=title or None,
            window_id=window_id,
            activate_target=False if bg else self.activate_target.isChecked(),
            multipoints=self._multipoints,
            background_to_app=bg,
        )
        self.statusBar().showMessage(
            f"Clicker started ({mode}"
            + (", background app)" if bg else ")")
            + f", {interval} ms"
        )
    def stop_all(self) -> None:
        if self._picking:
            self._stop_picking()
        if self.recorder.recording:
            self.recorder.stop()
        self.engine.stop()
        self._sync_status_pill()

    # ----- macros -----

    def _refresh_macro_list(self) -> None:
        current_id = self._selected_macro.id if self._selected_macro else None
        self.macro_list.clear()
        for macro in storage.list_macros():
            item = QListWidgetItem(f"{macro.name}  ({len(macro.steps)} steps)")
            item.setData(Qt.ItemDataRole.UserRole, macro.id)
            self.macro_list.addItem(item)
            if macro.id == current_id:
                self.macro_list.setCurrentItem(item)

    def _on_macro_selected(self, current: QListWidgetItem | None, _prev) -> None:
        if not current:
            self._selected_macro = None
            return
        macro = storage.get_macro(current.data(Qt.ItemDataRole.UserRole))
        if not macro:
            return
        self._selected_macro = macro
        self.macro_name.setText(macro.name)
        self.loop_spin.setValue(macro.loop_count)
        self.speed_spin.setValue(macro.speed)
        self.macro_activate.setChecked(macro.activate_before_play)
        self._load_steps_into_list(macro.steps)

    def _load_steps_into_list(self, steps: list[MacroStep]) -> None:
        self.step_list.clear()
        for step in steps:
            item = QListWidgetItem(step.label())
            item.setData(Qt.ItemDataRole.UserRole, step)
            self.step_list.addItem(item)

    def _current_steps_from_ui(self) -> list[MacroStep]:
        steps: list[MacroStep] = []
        for i in range(self.step_list.count()):
            step = self.step_list.item(i).data(Qt.ItemDataRole.UserRole)
            if isinstance(step, MacroStep):
                steps.append(step)
        return steps

    def _new_macro(self) -> None:
        name, bid, title = self._current_target()
        macro = Macro(
            name="New macro",
            steps=[],
            target_app_name=name or None,
            target_app_bundle_id=bid or None,
            target_window_title=title or None,
        )
        storage.save_macro(macro)
        self._selected_macro = macro
        self._refresh_macro_list()
        self.macro_name.setText(macro.name)
        self.loop_spin.setValue(1)
        self.speed_spin.setValue(1.0)
        self._load_steps_into_list([])

    def _delete_macro(self) -> None:
        if not self._selected_macro:
            return
        if (
            QMessageBox.question(self, "Delete", f"Delete “{self._selected_macro.name}”?")
            != QMessageBox.StandardButton.Yes
        ):
            return
        storage.delete_macro(self._selected_macro.id)
        self._selected_macro = None
        self.macro_name.clear()
        self._load_steps_into_list([])
        self._refresh_macro_list()

    def _import_macro(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "Import macro", "", "JSON (*.json)")
        if not path:
            return
        try:
            macro = storage.import_macro(__import__("pathlib").Path(path))
            self._selected_macro = macro
            self._refresh_macro_list()
            self.statusBar().showMessage(f"Imported “{macro.name}”")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "Import failed", str(exc))

    def _export_macro(self) -> None:
        if not self._selected_macro:
            return
        self._save_current_macro()
        path, _ = QFileDialog.getSaveFileName(
            self, "Export macro", f"{self._selected_macro.name}.json", "JSON (*.json)"
        )
        if not path:
            return
        from pathlib import Path

        storage.export_macro(self._selected_macro, Path(path))
        self.statusBar().showMessage(f"Exported to {path}")

    def _save_current_macro(self) -> None:
        name = self.macro_name.text().strip() or "Untitled"
        steps = self._current_steps_from_ui()
        tname, tbid, ttitle = self._current_target()
        if self._selected_macro:
            macro = self._selected_macro
            macro.name = name
            macro.steps = steps
            macro.loop_count = self.loop_spin.value()
            macro.speed = self.speed_spin.value()
            macro.activate_before_play = self.macro_activate.isChecked()
            if tbid or tname:
                macro.target_app_name = tname or None
                macro.target_app_bundle_id = tbid or None
                macro.target_window_title = ttitle or None
        else:
            macro = Macro(
                name=name,
                steps=steps,
                loop_count=self.loop_spin.value(),
                speed=self.speed_spin.value(),
                activate_before_play=self.macro_activate.isChecked(),
                target_app_name=tname or None,
                target_app_bundle_id=tbid or None,
                target_window_title=ttitle or None,
            )
            self._selected_macro = macro
        storage.save_macro(macro)
        self._refresh_macro_list()
        self.statusBar().showMessage(f"Saved “{macro.name}”")

    def _play_selected_macro(self) -> None:
        if not self._trusted_or_warn():
            return
        self._save_current_macro()
        if not self._selected_macro or not self._selected_macro.steps:
            QMessageBox.information(self, "Play", "Add some steps first.")
            return
        self.engine.play_macro(
            self._selected_macro,
            background_to_app=bool(hasattr(self, "bg_click") and self.bg_click.isChecked()),
        )

    def _add_step(self) -> None:
        dlg = StepEditorDialog(self)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            step = dlg.result_step()
            item = QListWidgetItem(step.label())
            item.setData(Qt.ItemDataRole.UserRole, step)
            self.step_list.addItem(item)

    def _edit_step(self) -> None:
        item = self.step_list.currentItem()
        if not item:
            return
        step = item.data(Qt.ItemDataRole.UserRole)
        dlg = StepEditorDialog(self, step)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            updated = dlg.result_step()
            item.setData(Qt.ItemDataRole.UserRole, updated)
            item.setText(updated.label())

    def _remove_step(self) -> None:
        row = self.step_list.currentRow()
        if row >= 0:
            self.step_list.takeItem(row)

    def _move_step(self, delta: int) -> None:
        row = self.step_list.currentRow()
        new_row = row + delta
        if row < 0 or new_row < 0 or new_row >= self.step_list.count():
            return
        item = self.step_list.takeItem(row)
        self.step_list.insertItem(new_row, item)
        self.step_list.setCurrentRow(new_row)

    def _quick_add_key(self) -> None:
        key, ok = QInputDialog.getText(self, "Key press", "Key (e.g. a, enter, space, f5):")
        if not ok or not key.strip():
            return
        self._append_step(MacroStep(type=StepType.KEY, key=key.strip(), delay_ms=50))

    def _quick_add_type(self) -> None:
        text, ok = QInputDialog.getText(self, "Type text", "Text to type:")
        if not ok or text == "":
            return
        self._append_step(MacroStep(type=StepType.TYPE, text=text, delay_ms=50))

    def _quick_add_delay(self) -> None:
        ms, ok = QInputDialog.getInt(self, "Delay", "Milliseconds:", 500, 0, 600_000)
        if not ok:
            return
        self._append_step(MacroStep(type=StepType.DELAY, delay_ms=ms))

    def _quick_add_click(self) -> None:
        from app.engine import _cursor_pos

        x, y = _cursor_pos()
        name, bid, title = self._current_target()
        kwargs = {
            "type": StepType.CLICK,
            "x": int(x),
            "y": int(y),
            "button": "left",
            "delay_ms": 50,
            "click_kind": "single",
            "coord_space": "screen",
        }
        if bid or name:
            w = winmod.find_window(
                bundle_id=bid or None, app_name=name or None, window_title=title or None
            )
            if w and winmod.point_in_window(x, y, w):
                lx, ly = winmod.screen_to_local(x, y, w)
                kwargs.update(
                    {
                        "coord_space": "window",
                        "local_x": float(lx),
                        "local_y": float(ly),
                        "app_bundle_id": w.bundle_id or None,
                        "app_name": w.app_name,
                        "window_title": w.title,
                    }
                )
        self._append_step(MacroStep(**kwargs))

    def _quick_add_activate(self) -> None:
        name, bid, _title = self._current_target()
        if not name and not bid:
            QMessageBox.information(self, "Activate", "Select a target app first.")
            return
        self._append_step(
            MacroStep(
                type=StepType.ACTIVATE_APP,
                app_name=name or None,
                app_bundle_id=bid or None,
                delay_ms=100,
            )
        )

    def _quick_add_wait_window(self) -> None:
        name, bid, title = self._current_target()
        self._append_step(
            MacroStep(
                type=StepType.WAIT_WINDOW,
                app_name=name or None,
                app_bundle_id=bid or None,
                window_title=title or None,
                timeout_ms=10_000,
                delay_ms=0,
            )
        )

    def _append_step(self, step: MacroStep) -> None:
        item = QListWidgetItem(step.label())
        item.setData(Qt.ItemDataRole.UserRole, step)
        self.step_list.addItem(item)

    # ----- record -----

    def toggle_recording(self) -> None:
        if self.recorder.recording:
            self.recorder.stop()
            self._sync_status_pill()
            return
        if not self._trusted_or_warn():
            return
        self.engine.stop()
        self.recorder.record_clicks = self.rec_clicks.isChecked()
        self.recorder.record_keys = self.rec_keys.isChecked()
        self.recorder.record_moves = self.rec_moves.isChecked()
        self.recorder.record_scroll = self.rec_scroll.isChecked()
        self.recorder.window_relative = self.rec_window_rel.isChecked()
        name, bid, title = self._current_target()
        if hasattr(self, "rec_use_target") and not self.rec_use_target.isChecked():
            name, bid, title = "", "", ""
        self.recorder.target_app_name = name or None
        self.recorder.target_bundle_id = bid or None
        self.recorder.target_window_title = title or None
        self.recorder.ignore_pids = winmod.our_app_pids() | {os.getpid()}
        self.recorder.start()
        self._sync_status_pill()

    def _clear_recording(self) -> None:
        self.recorder.clear()
        self._draft_steps = []
        self.record_list.clear()
        if hasattr(self, "rec_step_count"):
            self.rec_step_count.setText("0 steps")

    def _save_recording_as_macro(self) -> None:
        if not self._draft_steps:
            QMessageBox.information(self, "Save", "Nothing recorded yet.")
            return
        name, ok = QInputDialog.getText(self, "Save macro", "Name:", text="Recorded macro")
        if not ok:
            return
        tname, tbid, ttitle = self._current_target()
        macro = Macro(
            name=name.strip() or "Recorded macro",
            steps=list(self._draft_steps),
            target_app_name=tname or None,
            target_app_bundle_id=tbid or None,
            target_window_title=ttitle or None,
        )
        storage.save_macro(macro)
        self._selected_macro = macro
        self._refresh_macro_list()
        self.tabs.setCurrentIndex(1)
        self.statusBar().showMessage(f"Saved recording as “{macro.name}”")

    def _play_recording(self) -> None:
        if not self._trusted_or_warn():
            return
        if not self._draft_steps:
            QMessageBox.information(self, "Play", "Nothing recorded yet.")
            return
        tname, tbid, ttitle = self._current_target()
        macro = Macro(
            name="Recording",
            steps=list(self._draft_steps),
            loop_count=1,
            target_app_name=tname or None,
            target_app_bundle_id=tbid or None,
            target_window_title=ttitle or None,
            activate_before_play=self.activate_target.isChecked(),
        )
        self.engine.play_macro(
            macro,
            background_to_app=bool(hasattr(self, "bg_click") and self.bg_click.isChecked()),
        )

    # ----- settings -----

    def _apply_settings_to_form(self) -> None:
        self.int_h.setValue(int(self.settings.get("click_interval_h", 0)))
        self.int_m.setValue(int(self.settings.get("click_interval_m", 0)))
        self.int_s.setValue(int(self.settings.get("click_interval_s", 0)))
        self.int_ms.setValue(int(self.settings.get("click_interval_ms", 100)))
        self.button_combo.setCurrentText(str(self.settings.get("mouse_button", "left")))
        self.click_kind.setCurrentText(str(self.settings.get("click_kind", "single")))
        mode = self.settings.get("click_mode", "multipoint")
        if mode == "fixed":
            self.mode_fixed.setChecked(True)
        elif mode == "current":
            self.mode_current.setChecked(True)
        else:
            self.mode_multi.setChecked(True)
        self.fixed_x.setValue(int(self.settings.get("fixed_x", 0)))
        self.fixed_y.setValue(int(self.settings.get("fixed_y", 0)))
        self.repeat_spin.setValue(int(self.settings.get("repeat_count", 0)))
        self.jitter_spin.setValue(int(self.settings.get("jitter_ms", 0)))
        self.hk_toggle.set_binding(str(self.settings.get("hotkey_toggle", "<ctrl>+<alt>+a")))
        self.hk_record.set_binding(str(self.settings.get("hotkey_record", "<ctrl>+<alt>+r")))
        self.hk_stop.set_binding(str(self.settings.get("hotkey_stop", "<ctrl>+<alt>+s")))
        self.failsafe_check.setChecked(bool(self.settings.get("failsafe_pauses", True)))
        self.activate_target.setChecked(bool(self.settings.get("activate_target", False)))
        if hasattr(self, "rec_use_target"):
            self.rec_use_target.setChecked(bool(self.settings.get("record_use_target", True)))
        if hasattr(self, "bg_click"):
            self.bg_click.setChecked(bool(self.settings.get("background_to_app", False)))
            if hasattr(self, "target_bg_click"):
                self.target_bg_click.setChecked(self.bg_click.isChecked())
        self.rec_window_rel.setChecked(bool(self.settings.get("record_window_relative", True)))
        self._set_target(
            str(self.settings.get("target_app_name") or ""),
            str(self.settings.get("target_bundle_id") or ""),
            str(self.settings.get("target_window_title") or ""),
        )
        self._multipoints = list(self.settings.get("multipoints") or [])
        self._refresh_point_list()

    def _persist_clicker_settings(self) -> None:
        self.settings["click_interval_h"] = self.int_h.value()
        self.settings["click_interval_m"] = self.int_m.value()
        self.settings["click_interval_s"] = self.int_s.value()
        self.settings["click_interval_ms"] = self.int_ms.value()
        self.settings["mouse_button"] = self.button_combo.currentText()
        self.settings["click_kind"] = self.click_kind.currentText()
        if self.mode_fixed.isChecked():
            self.settings["click_mode"] = "fixed"
        elif self.mode_multi.isChecked():
            self.settings["click_mode"] = "multipoint"
        else:
            self.settings["click_mode"] = "current"
        self.settings["fixed_x"] = self.fixed_x.value()
        self.settings["fixed_y"] = self.fixed_y.value()
        self.settings["repeat_count"] = self.repeat_spin.value()
        self.settings["jitter_ms"] = self.jitter_spin.value()
        self.settings["activate_target"] = self.activate_target.isChecked()
        if hasattr(self, "rec_use_target"):
            self.settings["record_use_target"] = self.rec_use_target.isChecked()
        if hasattr(self, "bg_click"):
            self.settings["background_to_app"] = self.bg_click.isChecked()
        self.settings["record_window_relative"] = self.rec_window_rel.isChecked()
        self.settings["multipoints"] = self._multipoints
        storage.save_settings(self.settings)

    def _save_settings(self) -> None:
        self.settings["hotkey_toggle"] = self.hk_toggle.binding()
        self.settings["hotkey_record"] = self.hk_record.binding()
        self.settings["hotkey_stop"] = self.hk_stop.binding()
        self.settings["failsafe_pauses"] = self.failsafe_check.isChecked()
        self._persist_clicker_settings()
        storage.save_settings(self.settings)
        self._install_hotkeys()
        self.statusBar().showMessage("Settings saved")

    def _show_accessibility_help(self) -> None:
        QMessageBox.information(
            self,
            "Permissions",
            "System Settings → Privacy & Security → Accessibility "
            "(and Input Monitoring if hotkeys fail). Enable the app hosting Automater.",
        )

    def closeEvent(self, event: QCloseEvent) -> None:
        if self._picking:
            self._stop_picking()
        self.stop_all()
        self.hotkeys.stop()
        self._persist_clicker_settings()
        super().closeEvent(event)
