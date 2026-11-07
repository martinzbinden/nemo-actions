#!/bin/bash
# Voller Pfad zur PDF
f="$1"
# Ordnerpfad
p="${f%/*}"
# Pfad ohne Endung (.pdf)
b="${f%.*}"
# Nur der reine Dateiname ohne Pfad
n="${b##*/}"

# 1. Alle PDF-Seiten als temporäre PNGs mit 225 DPI extrahieren
pdftoppm -png -r 300 "$f" "${b}_tmp"

# Array für die erzeugten WebP-Dateien
created_files=()

# 2. Schleife durch alle erzeugten PNGs
for png in "${b}_tmp"-*.png; do
    [ -f "$png" ] || break

    # Seitennummer isolieren
    num=$(echo "$png" | grep -oE "[0-9]+\.png$" | cut -d. -f1)
    out="${b}_page${num}.webp"

    # Zu WebP konvertieren und PNG löschen
    cwebp -q 90 "$png" -o "$out"
    rm "$png"

    # Dateinamen für das ZIP-Archiv merken
    created_files+=("${n}_page${num}.webp")
done

# 3. Wenn Dateien erzeugt wurden, in ZIP packen (-m löscht die WebPs danach)
if [ ${#created_files[@]} -gt 0 ]; then
    cd "$p" && zip -m "${n}.zip" "${created_files[@]}"
fi

