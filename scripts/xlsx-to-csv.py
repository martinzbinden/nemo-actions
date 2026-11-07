#!/usr/bin/env python3
"""Nemo-Action: Excel-Datei in CSV-Dateien aufteilen, eine pro Tabellenblatt.

Aufruf:  xlsx-to-csv.py [--force] DATEI.xlsx [DATEI2.xlsx ...]

Neben "Budget 2026.xlsx" entsteht der Ordner "Budget 2026/" mit je einer
CSV-Datei pro Blatt, benannt nach dem Blatt. Formeln werden als berechnete
Werte exportiert. Existiert der Ordner schon und ist nicht leer, wird
nachgefragt (ausser mit --force).
"""
import csv
import datetime
import os
import re
import subprocess
import sys

import openpyxl

DELIMITER = ","        # für Schweizer Excel ";" einsetzen
ENCODING = "utf-8"     # "utf-8-sig", falls Excel die Umlaute falsch anzeigt
TITLE = "Excel → CSV"


def fmt(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, float):
        return str(int(v)) if v.is_integer() and abs(v) < 1e15 else repr(v)
    if isinstance(v, datetime.datetime):
        if v.time() == datetime.time(0):
            return v.date().isoformat()
        return v.isoformat(sep=" ")
    if isinstance(v, (datetime.date, datetime.time)):
        return v.isoformat()
    return str(v)


def sheet_rows(ws):
    """Zeilen als Text, ohne leere Zeilen/Spalten am Ende, alle gleich breit."""
    rows = []
    for row in ws.iter_rows(values_only=True):
        cells = [fmt(v) for v in row]
        while cells and cells[-1] == "":
            cells.pop()
        rows.append(cells)
    while rows and not rows[-1]:
        rows.pop()
    width = max((len(r) for r in rows), default=0)
    return [r + [""] * (width - len(r)) for r in rows]


def safe_name(name, used):
    name = re.sub(r'[/\\:*?"<>|\x00-\x1f]', "_", name).strip(" .") or "Blatt"
    out, i = name, 1
    while out.lower() in used:
        out = f"{name}-{i}"
        i += 1
    used.add(out.lower())
    return out


def zenity(*args):
    try:
        return subprocess.run(["zenity", f"--title={TITLE}", "--width=420", *args]).returncode == 0
    except FileNotFoundError:
        return False


def convert(path, force):
    """Gibt (Ordner, geschriebene Dateien, übersprungene leere Blätter) zurück, None bei Abbruch."""
    outdir = os.path.splitext(os.path.abspath(path))[0]
    if os.path.exists(outdir) and not os.path.isdir(outdir):
        raise RuntimeError(f"«{os.path.basename(outdir)}» existiert bereits und ist kein Ordner.")
    if os.path.isdir(outdir) and os.listdir(outdir) and not force:
        if not zenity("--question", f"--text=Der Ordner «{os.path.basename(outdir)}» existiert bereits.\n"
                                    "Gleichnamige CSV-Dateien darin überschreiben?"):
            return None
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        os.makedirs(outdir, exist_ok=True)
        written, empty, used = [], [], set()
        for ws in wb.worksheets:
            rows = sheet_rows(ws)
            if not rows:
                empty.append(ws.title)
                continue
            out = os.path.join(outdir, safe_name(ws.title, used) + ".csv")
            with open(out, "w", newline="", encoding=ENCODING) as f:
                csv.writer(f, delimiter=DELIMITER).writerows(rows)
            written.append(out)
    finally:
        wb.close()
    return outdir, written, empty


def main(argv):
    force = "--force" in argv
    files = [a for a in argv if a != "--force"]
    if not files:
        print(__doc__)
        return 1
    total, errors, notes = 0, [], []
    for path in files:
        try:
            res = convert(path, force)
        except Exception as e:      # defekte Datei, Passwortschutz, keine Schreibrechte ...
            errors.append(f"{os.path.basename(path)}: {e}")
            continue
        if res is None:
            continue
        outdir, written, empty = res
        total += len(written)
        print("\n".join(written))
        if empty:
            notes.append(f"{os.path.basename(path)}: leere Blätter übersprungen ({', '.join(empty)})")
    if errors:
        text = "\n".join(errors)
        print(text, file=sys.stderr)
        if not force:
            zenity("--error", f"--text={text}")
    if total and not force:
        body = f"{total} CSV-Dateien erstellt" + ("\n" + "\n".join(notes) if notes else "")
        subprocess.run(["notify-send", "-i", "x-office-spreadsheet", TITLE, body], check=False)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
