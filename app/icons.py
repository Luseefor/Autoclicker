"""macOS app icons → Qt (cached)."""

from __future__ import annotations

from PySide6.QtCore import QSize
from PySide6.QtGui import QIcon, QPixmap

_cache: dict[str, QIcon] = {}
_SIZE = 64


def _png_from_nsimage(nsimage, size: float = _SIZE) -> bytes | None:
    try:
        from AppKit import NSBitmapImageRep, NSCompositingOperationSourceOver, NSImage, NSPNGFileType
        from Foundation import NSMakeRect

        if nsimage is None:
            return None
        scaled = NSImage.alloc().initWithSize_((size, size))
        scaled.lockFocus()
        nsimage.drawInRect_fromRect_operation_fraction_(
            NSMakeRect(0, 0, size, size),
            NSMakeRect(0, 0, 0, 0),
            NSCompositingOperationSourceOver,
            1.0,
        )
        scaled.unlockFocus()
        tiff = scaled.TIFFRepresentation()
        if not tiff:
            return None
        rep = NSBitmapImageRep.imageRepWithData_(tiff)
        if rep is None:
            return None
        png = rep.representationUsingType_properties_(NSPNGFileType, None)
        return bytes(png) if png else None
    except Exception:
        return None


def _nsimage_for(pid: int | None = None, bundle_id: str | None = None):
    try:
        from AppKit import NSRunningApplication, NSWorkspace

        if pid is not None:
            app = NSRunningApplication.runningApplicationWithProcessIdentifier_(int(pid))
            if app is not None:
                icon = app.icon()
                if icon is not None:
                    return icon
                url = app.bundleURL()
                if url is not None:
                    return NSWorkspace.sharedWorkspace().iconForFile_(url.path())
        if bundle_id:
            apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(bundle_id)
            if apps:
                icon = apps[0].icon()
                if icon is not None:
                    return icon
                url = apps[0].bundleURL()
                if url is not None:
                    return NSWorkspace.sharedWorkspace().iconForFile_(url.path())
            # Not running — resolve from Launch Services style path via workspace
            ws = NSWorkspace.sharedWorkspace()
            url = ws.URLForApplicationWithBundleIdentifier_(bundle_id)
            if url is not None:
                return ws.iconForFile_(url.path())
    except Exception:
        return None
    return None


def icon_for(
    *,
    pid: int | None = None,
    bundle_id: str | None = None,
    size: int = 28,
) -> QIcon:
    key = bundle_id or (f"pid:{pid}" if pid is not None else "")
    if not key:
        return QIcon()
    cached = _cache.get(key)
    if cached is not None:
        return cached

    nsimage = _nsimage_for(pid=pid, bundle_id=bundle_id)
    png = _png_from_nsimage(nsimage) if nsimage is not None else None
    if not png:
        _cache[key] = QIcon()
        return _cache[key]

    pm = QPixmap()
    if not pm.loadFromData(png):
        _cache[key] = QIcon()
        return _cache[key]
    icon = QIcon(pm)
    _cache[key] = icon
    return icon


def pixmap_for(
    *,
    pid: int | None = None,
    bundle_id: str | None = None,
    size: int = 48,
) -> QPixmap:
    ic = icon_for(pid=pid, bundle_id=bundle_id)
    return ic.pixmap(QSize(size, size))


def clear_cache() -> None:
    _cache.clear()
