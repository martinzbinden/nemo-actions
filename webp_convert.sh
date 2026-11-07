#!/bin/bash
# Voller Pfad zur WebP-Datei
f="$1"
b="${f%.*}"

# 1. Grafischen Auswahldialog mit Zenity anzeigen
FORMAT=$(zenity --list --radiolist \
  --title="WebP umwandeln" \
  --column="Auswahl" --column="Zielformat" \
  TRUE "PNG" \
  FALSE "JPEG" \
  --width=300 --height=200)

# Abbrechen abfangen
if [ -z "$FORMAT" ]; then exit 1; fi

# 2. Formatkonvertierung basierend auf der Auswahl
case "$FORMAT" in
  PNG)
    # dwebp kann direkt nach PNG konvertieren
    dwebp "$f" -o "${b}.png"
    ;;
  JPEG)
    # Für JPEG konvertieren wir erst nach PNG und nutzen 'convert' (ImageMagick) für das finale JPG
    # Das sorgt für maximale Kompatibilität ohne Qualitätsverlust
    if command -v convert &> /dev/null; then
      dwebp "$f" -o "${b}_tmp.png"
      convert "${b}_tmp.png" "${b}.jpg"
      rm "${b}_tmp.png"
    else
      zenity --error --text="Fehler: 'imagemagick' ist nicht installiert. Bitte mit 'sudo apt install imagemagick' nachinstallieren."
    fi
    ;;
esac

