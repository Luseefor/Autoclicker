"""
Quiet modern skeuomorphism — soft cards, light depth, no XP chrome.
"""

APP_STYLE = """
* {
    outline: none;
}

QWidget {
    background-color: #e8eaef;
    color: #1a1d24;
    font-family: ".AppleSystemUIFont", "Helvetica Neue", Arial, sans-serif;
    font-size: 13px;
}

QMainWindow, QDialog {
    background-color: #e8eaef;
}

QLabel {
    background: transparent;
    color: #1a1d24;
    border: none;
}

QMenuBar {
    background: #e8eaef;
    border-bottom: 1px solid #d0d4dc;
    color: #1a1d24;
    padding: 2px;
}
QMenuBar::item {
    background: transparent;
    padding: 5px 10px;
    border-radius: 5px;
}
QMenuBar::item:selected {
    background: #dde1e8;
}

QLabel#brand {
    font-size: 18px;
    font-weight: 650;
    color: #111318;
    background: transparent;
}

QLabel#subtitle {
    color: #6b7280;
    font-size: 12px;
    background: transparent;
}

/* Keycaps — clean plastic, not XP bevel soup */
QLabel#keycap {
    background: #f7f8fa;
    color: #111318;
    border: 1px solid #c5cad3;
    border-bottom: 2px solid #9aa1ad;
    border-radius: 5px;
    padding: 3px 8px;
    font-size: 11px;
    font-weight: 600;
    min-height: 16px;
}
QLabel#keyPlus {
    color: #9aa1ad;
    font-size: 11px;
    background: transparent;
    padding: 0 2px;
}
QLabel#hotkeyCaption {
    color: #6b7280;
    font-size: 12px;
    background: transparent;
}
QWidget#hotkeyChip {
    background: #f3f4f7;
    border: 1px solid #d0d4dc;
    border-radius: 8px;
}
QWidget#hotkeyBar {
    background: transparent;
}
QWidget#hotkeyEditor {
    background: transparent;
}

QLabel#statusPill {
    background: #f3f4f7;
    color: #4b5563;
    border: 1px solid #d0d4dc;
    border-radius: 999px;
    padding: 5px 12px;
    font-weight: 600;
}
QLabel#statusPill[active="true"] {
    background: #e8f7ee;
    color: #166534;
    border-color: #86efac;
}
QLabel#statusPill[recording="true"],
QLabel#statusPill[picking="true"] {
    background: #fef2f2;
    color: #991b1b;
    border-color: #fca5a5;
}

QLabel#permBanner {
    background: #fffbeb;
    color: #92400e;
    border: 1px solid #fcd34d;
    border-radius: 8px;
    padding: 10px 12px;
}
QLabel#permName {
    background: transparent;
    font-weight: 600;
    color: #1a1d24;
}
QLabel#permBadge {
    background: #f3f4f7;
    color: #4b5563;
    border: 1px solid #d0d4dc;
    border-radius: 999px;
    padding: 2px 10px;
    font-size: 11px;
    font-weight: 650;
}
QLabel#permBadge[kind="ok"] {
    background: #e8f7ee;
    color: #166534;
    border-color: #86efac;
}
QLabel#permBadge[kind="need"] {
    background: #fef2f2;
    color: #991b1b;
    border-color: #fca5a5;
}
QLabel#permBadge[kind="maybe"] {
    background: #fffbeb;
    color: #92400e;
    border-color: #fcd34d;
}
QPushButton#linkBtn {
    background: transparent;
    border: none;
    border-bottom: none;
    color: #2563eb;
    font-weight: 600;
    padding: 4px 2px;
    min-height: 16px;
}
QPushButton#linkBtn:hover {
    background: transparent;
    color: #1d4ed8;
    text-decoration: underline;
}
QPushButton#linkBtn:pressed {
    background: transparent;
    padding-top: 4px;
    padding-bottom: 4px;
}
QPushButton#linkBtn:focus {
    border: none;
    outline: none;
}

QTabWidget::pane {
    border: 1px solid #d0d4dc;
    border-radius: 0 10px 10px 10px;
    background: #f7f8fa;
    top: -1px;
    padding: 8px;
}
QTabBar::tab {
    background: #dde1e8;
    color: #6b7280;
    padding: 9px 16px;
    margin-right: 2px;
    border: 1px solid #d0d4dc;
    border-bottom: none;
    border-top-left-radius: 8px;
    border-top-right-radius: 8px;
}
QTabBar::tab:selected {
    background: #f7f8fa;
    color: #111318;
    font-weight: 600;
    border-bottom: 1px solid #f7f8fa;
    margin-bottom: -1px;
}
QTabBar::tab:hover:!selected {
    background: #e8eaef;
    color: #374151;
}
QTabBar::tab:focus {
    outline: none;
}

/* Soft card — one light surface, thin edge */
QGroupBox {
    background: #ffffff;
    border: 1px solid #d0d4dc;
    border-radius: 12px;
    margin-top: 16px;
    padding: 20px 16px 16px 16px;
    font-weight: 600;
    color: #1a1d24;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 14px;
    padding: 0 8px;
    background: #ffffff;
    color: #374151;
}

QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QPlainTextEdit {
    background: #ffffff;
    color: #1a1d24;
    border: 1px solid #c5cad3;
    border-radius: 7px;
    padding: 6px 9px;
    min-height: 26px;
    selection-background-color: #2563eb;
    selection-color: #ffffff;
}
QLineEdit:focus, QSpinBox:focus, QDoubleSpinBox:focus, QComboBox:focus {
    border: 1px solid #2563eb;
}
QComboBox::drop-down {
    border: none;
    width: 22px;
}
QComboBox QAbstractItemView {
    background: #ffffff;
    color: #1a1d24;
    border: 1px solid #d0d4dc;
    selection-background-color: #eff6ff;
    selection-color: #111318;
    outline: none;
}

QListWidget {
    background: #f7f8fa;
    color: #1a1d24;
    border: 1px solid #d0d4dc;
    border-radius: 8px;
    outline: none;
    padding: 4px;
}
QListWidget#appList {
    background: #ffffff;
    padding: 6px;
}
QListWidget#appList::item {
    padding: 6px 10px 6px 6px;
    border-radius: 8px;
    margin: 1px 0;
}
QListWidget#stepList {
    background: #ffffff;
}
QListWidget#stepList::item {
    padding: 8px 12px;
}
QListWidget::item {
    padding: 8px 10px;
    border: none;
    border-radius: 6px;
    background: transparent;
}
QListWidget::item:selected {
    background: #eff6ff;
    color: #1e3a8a;
}
QListWidget::item:hover:!selected {
    background: #eef0f4;
}
QListWidget::item:focus {
    outline: none;
    border: none;
}

QLabel#cardTitle {
    font-size: 14px;
    font-weight: 650;
    color: #111318;
    background: transparent;
}
QLabel#sectionCaption {
    font-size: 11px;
    font-weight: 600;
    color: #6b7280;
    letter-spacing: 0.02em;
    background: transparent;
}
QFrame#softCard {
    background: #ffffff;
    border: 1px solid #d0d4dc;
    border-radius: 12px;
}
QLabel#appIconBadge {
    background: #f3f4f7;
    border: 1px solid #e5e7eb;
    border-radius: 12px;
    color: #9aa1ad;
    font-weight: 700;
}

QPushButton {
    background: #ffffff;
    border: 1px solid #c5cad3;
    border-bottom: 2px solid #a8afba;
    border-radius: 8px;
    padding: 8px 14px;
    color: #1a1d24;
    min-height: 22px;
    font-weight: 600;
}
QPushButton:hover {
    background: #f7f8fa;
    border-color: #a8afba;
}
QPushButton:pressed {
    background: #eef0f4;
    border-bottom: 1px solid #c5cad3;
    padding-top: 9px;
    padding-bottom: 7px;
}
QPushButton:focus {
    outline: none;
    border: 1px solid #2563eb;
    border-bottom: 2px solid #1d4ed8;
}

QPushButton#primary {
    background: #2563eb;
    border: 1px solid #1d4ed8;
    border-bottom: 2px solid #1e3a8a;
    color: #ffffff;
}
QPushButton#primary:hover {
    background: #3b82f6;
}
QPushButton#primary:pressed {
    background: #1d4ed8;
    border-bottom: 1px solid #1d4ed8;
}

QPushButton#danger {
    background: #ffffff;
    border: 1px solid #fca5a5;
    border-bottom: 2px solid #ef4444;
    color: #b91c1c;
}
QPushButton#danger:hover {
    background: #fef2f2;
}
QPushButton#danger:pressed {
    background: #fee2e2;
    border-bottom: 1px solid #fca5a5;
}

QCheckBox, QRadioButton {
    spacing: 8px;
    color: #1a1d24;
    background: transparent;
}
QCheckBox::indicator, QRadioButton::indicator {
    width: 15px;
    height: 15px;
    background: #ffffff;
    border: 1px solid #c5cad3;
}
QCheckBox::indicator {
    border-radius: 4px;
}
QRadioButton::indicator {
    border-radius: 8px;
}
QCheckBox::indicator:checked {
    background: #2563eb;
    border-color: #1d4ed8;
}
QRadioButton::indicator:checked {
    background: #2563eb;
    border-color: #1d4ed8;
}
QCheckBox:focus, QRadioButton:focus {
    outline: none;
}

QStatusBar {
    background: #e8eaef;
    color: #6b7280;
    border-top: 1px solid #d0d4dc;
}
QSplitter::handle {
    background: #d0d4dc;
}
QToolTip {
    background: #ffffff;
    color: #1a1d24;
    border: 1px solid #d0d4dc;
    padding: 6px 8px;
    border-radius: 6px;
}
"""
