#!/usr/bin/env python3
"""Hilfsprogramm für rip-cd.sh: MusicBrainz-Disc-ID und Metadaten.

  rip-cd-lookup.py discid            TOC (Ausgabe von cdparanoia -Q) auf stdin -> Disc-ID
  rip-cd-lookup.py releases DISCID   Treffer als "Index<TAB>Interpret - Album (Jahr)"
  rip-cd-lookup.py tracks DISCID N   Treffer N -> "Interpret<TAB>Album<TAB>Jahr<TAB>Nr<TAB>Titel"

Gesendet wird nur die Disc-ID (kein Konto, keine Dateinamen).
"""
import base64
import hashlib
import json
import re
import sys
import urllib.request

UA = "nemo-rip-cd/1.0 (https://github.com/martinzbinden/nemo-actions)"


def discid(toc):
    tracks = [(int(m[1]), int(m[2]), int(m[3])) for m in
              re.finditer(r"^\s*(\d+)\.\s+(\d+)\s+\[[^\]]*\]\s+(\d+)", toc, re.M)]
    if not tracks:
        sys.exit("Kein Inhaltsverzeichnis gefunden")
    offsets = [s + 150 for _, _, s in tracks]
    leadout = tracks[-1][2] + tracks[-1][1] + 150
    h = "%02X%02X%08X" % (tracks[0][0], tracks[-1][0], leadout)
    h += "".join("%08X" % o for o in offsets) + "00000000" * (99 - len(offsets))
    d = base64.b64encode(hashlib.sha1(h.encode()).digest()).decode()
    return d.translate(str.maketrans("+/=", "._-"))


def fetch(disc):
    url = f"https://musicbrainz.org/ws/2/discid/{disc}?inc=recordings+artist-credits&fmt=json"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=15) as r:
            return json.load(r).get("releases", [])
    except Exception:
        return []


def artist(rel):
    return "".join(a["name"] + a.get("joinphrase", "") for a in rel["artist-credit"])


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    if argv[0] == "discid":
        print(discid(sys.stdin.read()))
    elif argv[0] == "releases":
        for i, r in enumerate(fetch(argv[1])):
            print(f"{i}\t{artist(r)} - {r['title']} ({r.get('date', '')[:4]})")
    elif argv[0] == "tracks":
        r = fetch(argv[1])[int(argv[2])]
        for t in r["media"][0]["tracks"] if len(r["media"]) == 1 else \
                [t for m in r["media"] if any(d["id"] == argv[1] for d in m.get("discs", [])) for t in m["tracks"]]:
            print("\t".join([artist(r), r["title"], r.get("date", "")[:4], t["number"], t["title"]]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
