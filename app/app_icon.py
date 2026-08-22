"""Programmatic Automater app icon — no external assets required."""

from __future__ import annotations

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (
    QBrush,
    QColor,
    QIcon,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
    QPolygonF,
)

_SIZES = (16, 22, 32, 44, 64, 128, 256, 512)

# Classic pointer silhouette in a ~24-unit box, scaled into the badge.
_CURSOR = [
    (0.0, 0.0), (0.0, 17.0), (4.2, 13.4), (6.8, 19.3),
    (9.2, 18.2), (6.6, 12.5), (11.9, 12.0),
]


def _draw(painter: QPainter, size: int) -> None:
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    s = size / 512.0

    grad = QLinearGradient(0, 0, size, size)
    grad.setColorAt(0.0, QColor("#3b82f6"))
    grad.setColorAt(1.0, QColor("#1d4ed8"))
    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(QBrush(grad))
    painter.drawRoundedRect(QRectF(0, 0, size, size), 110 * s, 110 * s)

    cx, cy = 355 * s, 175 * s
    pen = QPen(QColor(255, 255, 255, 210))
    pen.setWidthF(26 * s)
    pen.setCapStyle(Qt.PenCapStyle.RoundCap)
    painter.setPen(pen)
    painter.setBrush(Qt.BrushStyle.NoBrush)
    for r in (62 * s, 122 * s):
        rect = QRectF(cx - r, cy - r, 2 * r, 2 * r)
        path = QPainterPath()
        path.moveTo(cx + r, cy)
        path.arcTo(rect, 0, -105)
        painter.drawPath(path)

    k = 21.5 * s
    off_x, off_y = 128 * s, 78 * s
    poly = QPolygonF([QPointF(px * k + off_x, py * k + off_y) for px, py in _CURSOR])
    outline = QPen(
        QColor("#0b1220"),
        max(1.0, 13 * s),
        Qt.PenStyle.SolidLine,
        Qt.PenCapStyle.RoundCap,
        Qt.PenJoinStyle.RoundJoin,
    )
    painter.setPen(outline)
    painter.setBrush(QColor("#ffffff"))
    painter.drawPolygon(poly)


def build_app_icon() -> QIcon:
    icon = QIcon()
    for size in _SIZES:
        pm = QPixmap(size, size)
        pm.fill(Qt.GlobalColor.transparent)
        p = QPainter(pm)
        try:
            _draw(p, size)
        finally:
            p.end()
        icon.addPixmap(pm)
    return icon


def apply_dock_icon(icon: QIcon) -> None:
    """Mirror the icon onto the macOS Dock (no-op when unavailable)."""
    try:
        from Foundation import NSData
        from AppKit import NSApplication, NSImage
        from PySide6.QtCore import QBuffer, QIODevice

        pm = icon.pixmap(512, 512)
        buf = QBuffer()
        buf.open(QIODevice.OpenModeFlag.WriteOnly)
        pm.save(buf, "PNG")
        raw = bytes(buf.data())
        data = NSData.dataWithBytes_length_(raw, len(raw))
        nsimg = NSImage.alloc().initWithData_(data)
        if nsimg is not None:
            NSApplication.sharedApplication().setApplicationIconImage_(nsimg)
    except Exception:
        pass
