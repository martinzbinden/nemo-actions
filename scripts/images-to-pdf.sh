#!/bin/bash
# Nemo-Action: Bilddateien nach PDF umwandeln (für Paperless-Export).
# Aufruf: images-to-pdf.sh BILD1 [BILD2 ...]
# - Eine Datei: BILD.pdf daneben.
# - Mehrere Dateien: Dialog "je ein PDF" oder "ein gemeinsames PDF".
# Nutzt img2pdf (verlustfrei, EXIF-Rotation beachtet); Formate, die img2pdf
# nicht direkt kann (z.B. HEIC), werden per ImageMagick nach PNG vorgewandelt.

set -u
[ $# -eq 0 ] && exit 0

TMPDIR_CONV=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CONV"' EXIT

# Gibt einen Pfad zurück, den img2pdf lesen kann (ggf. nach PNG konvertiert).
prepare() {
    local f="$1" ext="${1##*.}"
    case "${ext,,}" in
        jpg|jpeg|png|tif|tiff|gif|bmp|webp|jp2|j2k) printf '%s' "$f" ;;
        *)  local out="$TMPDIR_CONV/$(basename "${f%.*}").png"
            convert "$f" -auto-orient "$out" 2>/dev/null && printf '%s' "$out" || printf '%s' "$f" ;;
    esac
}

# Eindeutigen Zielnamen finden (überschreibt nichts).
unique() {
    local base="$1" out="$1.pdf" n=1
    while [ -e "$out" ]; do out="$base-$n.pdf"; n=$((n+1)); done
    printf '%s' "$out"
}

to_pdf() {   # to_pdf ZIEL.pdf BILD...
    local out="$1"; shift
    local inputs=() f
    for f in "$@"; do inputs+=("$(prepare "$f")"); done
    python3 -m img2pdf --rotation auto -o "$out" "${inputs[@]}" 2>"$TMPDIR_CONV/err"
}

MODE=einzeln
if [ $# -gt 1 ]; then
    MODE=$(zenity --list --radiolist --title="Bilder → PDF" \
        --text="$# Bilder ausgewählt. Wie umwandeln?" \
        --column="" --column="Modus" --column="Beschreibung" --hide-column=2 --print-column=2 \
        TRUE einzeln "Je ein PDF pro Bild" \
        FALSE zusammen "Ein gemeinsames PDF (Seiten in Auswahlreihenfolge)" \
        --width=420 --height=220) || exit 0
fi

ok=0; fail=0; failmsg=""
if [ "$MODE" = "zusammen" ]; then
    first="$1"
    default="$(basename "${first%.*}")"
    name=$(zenity --entry --title="Bilder → PDF" --text="Dateiname für das gemeinsame PDF (ohne .pdf):" \
        --entry-text="$default") || exit 0
    [ -z "$name" ] && name="$default"
    out=$(unique "$(dirname "$first")/${name%.pdf}")
    if to_pdf "$out" "$@"; then ok=$#; else fail=$#; failmsg=$(<"$TMPDIR_CONV/err"); fi
    result="$out"
else
    for f in "$@"; do
        out=$(unique "${f%.*}")
        if to_pdf "$out" "$f"; then ok=$((ok+1)); else fail=$((fail+1)); failmsg+="$(basename "$f"): $(tail -n1 "$TMPDIR_CONV/err")"$'\n'; fi
    done
    result="$(dirname "$1")"
fi

if [ $fail -eq 0 ]; then
    notify-send -i application-pdf "Bilder → PDF" "$ok PDF erstellt in $(basename "$(dirname "$1")")"
else
    zenity --error --title="Bilder → PDF" --text="$ok OK, $fail fehlgeschlagen:\n\n$failmsg" --width=400
fi
