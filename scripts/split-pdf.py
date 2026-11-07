#!/usr/bin/env python3
"""Nemo-Action: PDF trennen, mit Seitenvorschau.

Aufruf:  split-pdf.py DATEI.pdf [DATEI2.pdf ...]      Dialog pro Datei
         split-pdf.py --at 3,5 DATEI.pdf               ohne Dialog: neue Teile
                                                       beginnen bei Seite 3 und 5

Die Teile landen neben dem Original als NAME_S1-2.pdf, NAME_S3-4.pdf, ...
Das Original bleibt unverändert, bestehende Dateien werden nie überschrieben.
Vorschau: PyMuPDF (fitz). Trennen: pikepdf (verlustfrei).
"""
import os
import subprocess
import sys

import pikepdf

THUMB_W, THUMB_H = 190, 260   # Feld für die Seitenvorschau in Pixel (Seite wird eingepasst)
TITLE = "PDF trennen"


# ---------- Logik (ohne GUI) ----------

def ranges_from_cuts(cuts, n):
    """cuts: 0-basierte Seitenindizes, an denen ein neuer Teil beginnt."""
    starts = [0] + sorted(c for c in set(cuts) if 0 < c < n)
    return [(s, e) for s, e in zip(starts, starts[1:] + [n])]


def unique(path):
    base, ext = os.path.splitext(path)
    out, i = path, 1
    while os.path.exists(out):
        out = f"{base}-{i}{ext}"
        i += 1
    return out


def split_pdf(path, cuts):
    """Schreibt die Teile neben das Original, gibt die Liste der Dateien zurück."""
    base = os.path.splitext(path)[0]
    outputs = []
    with pikepdf.open(path) as src:
        n = len(src.pages)
        w = len(str(n))
        for a, b in ranges_from_cuts(cuts, n):
            pages = f"{a + 1:0{w}d}" if b - a == 1 else f"{a + 1:0{w}d}-{b:0{w}d}"
            out = unique(f"{base}_S{pages}.pdf")
            dst = pikepdf.new()
            dst.pages.extend(src.pages[a:b])
            dst.save(out)
            outputs.append(out)
    return outputs


# ---------- Dialog ----------

CSS = b"""
.cut { padding: 0; min-width: 28px; border-radius: 4px; opacity: 0.55; font-size: 150%; }
.cut:hover { opacity: 1; }
.cut:checked { opacity: 1; background-image: none; background-color: #d9372c;
               color: white; border-color: #a3261e; }
.page { padding: 6px; border-radius: 5px; }
.page label { color: #222; }
.part0 { background-color: #cfe2ff; }
.part1 { background-color: #ffe2b3; }
"""


def run_dialog(path):
    """Zeigt den Dialog. Rückgabe: Liste der Schnittstellen oder None (Abbruch)."""
    import fitz
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

    doc = fitz.open(path)
    if doc.needs_pass:
        raise RuntimeError("Das PDF ist passwortgeschützt.")
    n = doc.page_count
    if n < 2:
        raise RuntimeError("Das PDF hat nur eine Seite, es gibt nichts zu trennen.")

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    state = {"result": None, "busy": False}
    win = Gtk.Window(title=f"{TITLE}: {os.path.basename(path)}")
    win.set_default_size(1000, 720)
    win.set_position(Gtk.WindowPosition.CENTER)
    win.set_icon_name("application-pdf")
    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=10)
    win.add(outer)

    hint = Gtk.Label(xalign=0)
    hint.set_markup(f"<b>{GLib.markup_escape_text(os.path.basename(path))}</b>  ({n} Seiten)\n"
                    "Klicke auf ✂ zwischen zwei Seiten, um dort zu trennen. "
                    "Gleiche Farbe = gleiche Datei.")
    outer.pack_start(hint, False, False, 0)

    flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=False,
                       max_children_per_line=50, row_spacing=10, column_spacing=0,
                       valign=Gtk.Align.START)
    scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    scroll.add(flow)
    outer.pack_start(scroll, True, True, 0)

    cut_btns, page_boxes, images = {}, [], []
    for i in range(n):
        cell = Gtk.Box(spacing=2)
        if i > 0:
            btn = Gtk.ToggleButton(label="✂", can_focus=False)
            btn.get_style_context().add_class("cut")
            btn.set_tooltip_text(f"Vor Seite {i + 1} trennen")
            cut_btns[i] = btn
            cell.pack_start(btn, False, False, 0)
        else:
            cell.pack_start(Gtk.Box(width_request=28), False, False, 0)
        img = Gtk.Image()
        img.set_size_request(THUMB_W, THUMB_H)
        pbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        pbox.get_style_context().add_class("page")
        pbox.pack_start(img, False, False, 0)
        pbox.pack_start(Gtk.Label(label=f"Seite {i + 1}"), False, False, 0)
        cell.pack_start(pbox, False, False, 0)
        child = Gtk.FlowBoxChild(can_focus=False)
        child.add(cell)
        flow.add(child)
        page_boxes.append(pbox)
        images.append(img)

    # Fusszeile
    bar = Gtk.Box(spacing=6)
    outer.pack_start(bar, False, False, 0)
    bar.pack_start(Gtk.Label(label="Alle"), False, False, 0)
    spin = Gtk.SpinButton.new_with_range(1, n - 1, 1)
    bar.pack_start(spin, False, False, 0)
    bar.pack_start(Gtk.Label(label="Seiten trennen"), False, False, 0)
    every = Gtk.Button(label="Anwenden")
    reset = Gtk.Button(label="Zurücksetzen")
    bar.pack_start(every, False, False, 0)
    bar.pack_start(reset, False, False, 0)
    status = Gtk.Label(xalign=1)
    bar.pack_start(status, True, True, 0)
    cancel = Gtk.Button(label="Abbrechen")
    ok = Gtk.Button(label="Trennen")
    ok.get_style_context().add_class("suggested-action")
    bar.pack_start(cancel, False, False, 0)
    bar.pack_start(ok, False, False, 0)

    def cuts():
        return [i for i, b in cut_btns.items() if b.get_active()]

    def refresh(*_):
        if state["busy"]:
            return
        c = set(cuts())
        part = 0
        for i, pbox in enumerate(page_boxes):
            if i in c:
                part += 1
            ctx = pbox.get_style_context()
            ctx.remove_class("part0")
            ctx.remove_class("part1")
            ctx.add_class(f"part{part % 2}")
        ok.set_sensitive(bool(c))
        status.set_text(f"{len(c) + 1} Dateien werden erstellt" if c else "Noch keine Trennstelle gewählt")

    def set_cuts(wanted):
        state["busy"] = True
        for i, b in cut_btns.items():
            b.set_active(i in wanted)
        state["busy"] = False
        refresh()

    def finish(_):
        state["result"] = cuts()
        win.destroy()

    for b in cut_btns.values():
        b.connect("toggled", refresh)
    every.connect("clicked", lambda _: set_cuts(set(range(spin.get_value_as_int(), n, spin.get_value_as_int()))))
    reset.connect("clicked", lambda _: set_cuts(set()))
    cancel.connect("clicked", lambda _: win.destroy())
    ok.connect("clicked", finish)
    win.connect("key-press-event", lambda w, e: e.keyval == Gdk.KEY_Escape and (win.destroy() or True))
    win.connect("destroy", lambda _: Gtk.main_quit())

    # Vorschauen nach und nach rendern, damit der Dialog sofort erscheint
    def render():
        for i in range(n):
            page = doc[i]
            zoom = min(THUMB_W / max(page.rect.width, 1), THUMB_H / max(page.rect.height, 1))
            pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
            pb = GdkPixbuf.Pixbuf.new_from_bytes(
                GLib.Bytes.new(pix.samples), GdkPixbuf.Colorspace.RGB, False, 8,
                pix.width, pix.height, pix.stride)
            images[i].set_from_pixbuf(pb)
            yield True
        yield False

    gen = render()
    GLib.idle_add(lambda: next(gen))

    refresh()
    win.show_all()
    Gtk.main()
    doc.close()
    return state["result"]


def message(text, error=False):
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
        d = Gtk.MessageDialog(message_type=Gtk.MessageType.ERROR if error else Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.OK, text=TITLE, secondary_text=text)
        d.run()
        d.destroy()
    except Exception:
        print(text, file=sys.stderr)


def main(argv):
    preset = None
    if len(argv) >= 2 and argv[0] == "--at":
        preset = [int(x) - 1 for x in argv[1].split(",") if x.strip()]
        argv = argv[2:]
    if not argv:
        print(__doc__)
        return 1
    created, rc = [], 0
    for path in argv:
        try:
            cuts = preset if preset is not None else run_dialog(path)
            if not cuts:
                continue
            created += split_pdf(path, cuts)
        except Exception as e:            # z.B. Passwortschutz, defektes PDF
            rc = 1
            msg = f"{os.path.basename(path)}:\n{e}"
            print(msg, file=sys.stderr) if preset is not None else message(msg, error=True)
    if created:
        text = f"{len(created)} Dateien erstellt in {os.path.basename(os.path.dirname(os.path.abspath(created[0])))}"
        print("\n".join(created))
        if preset is None:
            subprocess.run(["notify-send", "-i", "application-pdf", TITLE, text], check=False)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
