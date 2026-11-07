#!/bin/bash
# Nemo-Action: Audio-CD als Opus (128 kbit/s) rippen.
# Aufruf: rip-cd.sh ZIELORDNER
# Ergebnis: ZIELORDNER/Interpret/Album/NN Titel.opus (Struktur für Jellyfin).
# Metadaten per MusicBrainz (sendet nur die Disc-ID), sonst manuelle Eingabe.
# Laufwerk: $CDDEV, sonst /dev/cdrom.

set -u
TITLE="Audio-CD rippen"
BITRATE=128
DEV="${CDDEV:-/dev/cdrom}"
DEST="${1:-$PWD}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOOKUP="$HERE/rip-cd-lookup.py"

fail() { zenity --error --title="$TITLE" --width=380 --text="$1"; exit 1; }

# Dateinamen: unzulässige Zeichen (auch für SMB/Windows) entfernen
safe() { printf '%s' "${1//\?\?\?/Fragezeichen}" | tr -d '\\/:*?"<>|' | sed -E 's/^[ .]+|[ .]+$//g; s/  +/ /g'; }

TOC=$(cdparanoia -Q -d "$DEV" 2>&1)
NTRACKS=$(grep -cE '^\s*[0-9]+\.\s+[0-9]+ \[' <<<"$TOC")
[ "$NTRACKS" -gt 0 ] || fail "Keine Audio-CD im Laufwerk $DEV gefunden."
DISCID=$("$LOOKUP" discid <<<"$TOC") || fail "Disc-ID konnte nicht berechnet werden."

ARTIST=""; ALBUM=""; YEAR=""; declare -a NAMES=()

if zenity --question --title="$TITLE" --width=420 --ok-label="Abfragen" --cancel-label="Manuell" \
     --text="$NTRACKS Titel gefunden.\n\nInterpret, Album und Titel bei MusicBrainz abfragen?\nDabei wird nur die Disc-ID gesendet:\n$DISCID"; then
  mapfile -t REL < <("$LOOKUP" releases "$DISCID")
  IDX=""
  if [ ${#REL[@]} -eq 1 ]; then
    IDX=0
  elif [ ${#REL[@]} -gt 1 ]; then
    ARGS=(); for l in "${REL[@]}"; do ARGS+=("${l%%$'\t'*}" "${l#*$'\t'}"); done
    IDX=$(zenity --list --title="$TITLE" --width=560 --height=300 --text="Mehrere Treffer:" \
      --column=Nr --column=Release --hide-column=1 --print-column=1 "${ARGS[@]}") || exit 0
  fi
  if [ -n "$IDX" ]; then
    while IFS=$'\t' read -r a al y n t; do
      ARTIST="$a"; ALBUM="$al"; YEAR="$y"; NAMES[$((10#$n))]="$t"
    done < <("$LOOKUP" tracks "$DISCID" "$IDX")
  else
    zenity --info --title="$TITLE" --text="Kein Treffer bei MusicBrainz. Bitte manuell eingeben."
  fi
fi

if [ -z "$ARTIST" ]; then
  IN=$(zenity --forms --title="$TITLE" --width=420 --text="Metadaten ($NTRACKS Titel)" \
    --add-entry="Interpret" --add-entry="Album" --add-entry="Jahr (optional)" --separator=$'\t') || exit 0
  IFS=$'\t' read -r ARTIST ALBUM YEAR <<<"$IN"
  [ -n "$ARTIST" ] && [ -n "$ALBUM" ] || fail "Interpret und Album werden benötigt."
fi

OUT="$DEST/$(safe "$ARTIST")/$(safe "$ALBUM")"
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then
  zenity --question --title="$TITLE" --width=420 --text="Der Ordner existiert schon und ist nicht leer:\n$OUT\n\nTrotzdem rippen (gleichnamige Dateien werden überschrieben)?" || exit 0
fi
mkdir -p "$OUT" || fail "Zielordner kann nicht angelegt werden:\n$OUT"

# Rippen und direkt nach Opus kodieren, mit Fortschrittsanzeige
(
  for ((n = 1; n <= NTRACKS; n++)); do
    name="${NAMES[$n]:-Track $n}"
    echo "# Titel $n von $NTRACKS: $name"
    num=$(printf '%02d' "$n")
    cdparanoia -q -d "$DEV" -w "$n" - 2>/dev/null | opusenc --quiet --bitrate "$BITRATE" \
      --title "$name" --artist "$ARTIST" --album "$ALBUM" --tracknumber "$n" \
      ${YEAR:+--date "$YEAR"} --comment "ALBUMARTIST=$ARTIST" --comment "TRACKTOTAL=$NTRACKS" \
      - "$OUT/$num $(safe "$name").opus" || { echo "FEHLER bei Titel $n" >&2; exit 1; }
    echo $((n * 100 / NTRACKS))
  done
) | zenity --progress --title="$TITLE" --width=460 --auto-close --percentage=0 \
    --text="Starte …" || { zenity --error --title="$TITLE" --text="Abgebrochen oder fehlgeschlagen. Bereits erzeugte Dateien liegen in:\n$OUT"; exit 1; }

eject "$DEV" 2>/dev/null
notify-send -i media-optical-audio "$TITLE" "$NTRACKS Titel nach $ARTIST/$ALBUM" 2>/dev/null
