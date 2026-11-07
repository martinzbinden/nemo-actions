#!/bin/bash
# Manuell beidseitig drucken (Nemo-Aktion für Linux Mint)
# Druckt zuerst die ungeraden, nach Bestätigung die geraden Seiten.
# Mehrere Exemplare: jedes Exemplar beginnt auf einem neuen Blatt.

CONF="$HOME/.config/manual-duplex.conf"
LAST_PRINTER=""
REVERSE_EVEN=1            # 1 = gerade Seiten in umgekehrter Reihenfolge
[ -f "$CONF" ] && source "$CONF"

FILE="$1"
TITLE="Manuell beidseitig drucken"
MAX_COPIES=20

fail() { zenity --error --title="$TITLE" --width=380 --text="$1"; exit 1; }

[ -f "$FILE" ] || fail "Datei nicht gefunden:\n$FILE"
command -v lp >/dev/null       || fail "Der Befehl 'lp' (CUPS) fehlt."
command -v pdfinfo >/dev/null  || fail "'pdfinfo' fehlt.\nInstallieren mit:  sudo apt install poppler-utils"
command -v pdfunite >/dev/null || fail "'pdfunite' fehlt.\nInstallieren mit:  sudo apt install poppler-utils"

NAME=$(basename "$FILE")

# --- Seitenzahl -------------------------------------------------------------
PAGES=$(pdfinfo "$FILE" 2>/dev/null | awk '/^Pages:/ {print $2}')
[[ "$PAGES" =~ ^[0-9]+$ ]] || fail "Seitenzahl konnte nicht gelesen werden.\nIst die Datei ein gültiges PDF?"

# --- Drucker, Exemplare, Reihenfolge wählen --------------------------------
mapfile -t PRINTERS < <(lpstat -e 2>/dev/null)
[ ${#PRINTERS[@]} -gt 0 ] || fail "Kein Drucker gefunden."

DEFAULT=$(LC_ALL=C lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p')
FIRST="${LAST_PRINTER:-$DEFAULT}"

# Zuletzt benutzten Drucker an den Anfang der Liste stellen
LIST="$FIRST"
for p in "${PRINTERS[@]}"; do
  [ "$p" != "$FIRST" ] && LIST="${LIST:+$LIST|}$p"
done
LIST="${LIST#|}"

COPYLIST=$(seq -s '|' 1 "$MAX_COPIES")

if [ "$REVERSE_EVEN" = "1" ]; then
  ORDERS="Umgekehrt (Standard)|Normal"
else
  ORDERS="Normal|Umgekehrt (Standard)"
fi

CHOICE=$(zenity --forms --title="$TITLE" --width=420 \
  --text="$NAME  –  $PAGES Seiten" \
  --add-combo="Drucker" --combo-values="$LIST" \
  --add-combo="Exemplare" --combo-values="$COPYLIST" \
  --add-combo="Rückseiten-Reihenfolge" --combo-values="$ORDERS" \
  --separator="|") || exit 0

IFS='|' read -r PRINTER COPIES ORDER <<< "$CHOICE"
# Leere Auswahl = erster Eintrag
[ -z "$PRINTER" ] && PRINTER="${LIST%%|*}"
[[ "$COPIES" =~ ^[0-9]+$ ]] || COPIES=1
[ -z "$ORDER" ]   && ORDER="${ORDERS%%|*}"
[[ "$ORDER" == Umgekehrt* ]] && REVERSE_EVEN=1 || REVERSE_EVEN=0

mkdir -p "$(dirname "$CONF")"
printf 'LAST_PRINTER=%q\nREVERSE_EVEN=%s\n' "$PRINTER" "$REVERSE_EVEN" > "$CONF"

# --- Nur eine Seite: normal drucken ----------------------------------------
if [ "$PAGES" -le 1 ]; then
  lp -d "$PRINTER" -n "$COPIES" -t "$NAME" "$FILE" >/dev/null || fail "Druckauftrag fehlgeschlagen."
  notify-send -i printer "$TITLE" "Nur 1 Seite – normal gedruckt ($COPIES×)." 2>/dev/null
  exit 0
fi

# --- Mehrere Exemplare: zu einem PDF zusammenfügen -------------------------
# Hat das Dokument eine ungerade Seitenzahl, kommt zwischen die Exemplare
# eine Leerseite, damit jedes Exemplar auf einem neuen Blatt beginnt.
make_blank() {   # make_blank BREITE HÖHE DATEI  (Masse in pt)
  local o1="1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
  local o2="2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
  local o3="3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $1 $2] >>\nendobj\n"
  local hdr="%%PDF-1.4\n"
  local LC_ALL=C
  local a b c x
  a=$(printf "$hdr" | wc -c)
  b=$((a + $(printf "$o1" | wc -c)))
  c=$((b + $(printf "$o2" | wc -c)))
  x=$((c + $(printf "$o3" | wc -c)))
  {
    printf "$hdr$o1$o2$o3"
    printf 'xref\n0 4\n0000000000 65535 f \n%010d 00000 n \n%010d 00000 n \n%010d 00000 n \n' "$a" "$b" "$c"
    printf 'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' "$x"
  } > "$3"
}

PRINTFILE="$FILE"
if [ "$COPIES" -gt 1 ]; then
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  PARTS=()
  if [ $((PAGES % 2)) -eq 1 ]; then
    read -r W H < <(pdfinfo -f "$PAGES" -l "$PAGES" "$FILE" 2>/dev/null \
                    | awk '/^Page.*size:/ {print $(NF-3), $(NF-1); exit}')
    [[ "$W" =~ ^[0-9.]+$ && "$H" =~ ^[0-9.]+$ ]] || { W=595.28; H=841.89; }   # Fallback A4
    make_blank "$W" "$H" "$TMPDIR/blank.pdf"
  fi
  for ((i = 1; i <= COPIES; i++)); do
    PARTS+=("$FILE")
    [ $i -lt "$COPIES" ] && [ -f "$TMPDIR/blank.pdf" ] && PARTS+=("$TMPDIR/blank.pdf")
  done
  pdfunite "${PARTS[@]}" "$TMPDIR/combined.pdf" 2>/dev/null \
    || fail "Exemplare konnten nicht zusammengefügt werden."
  PRINTFILE="$TMPDIR/combined.pdf"
  PAGES=$(pdfinfo "$PRINTFILE" | awk '/^Pages:/ {print $2}')
fi

# --- Durchgang 1: ungerade Seiten ------------------------------------------
lp -d "$PRINTER" -o page-set=odd -t "$NAME (Vorderseiten)" "$PRINTFILE" >/dev/null \
  || fail "Druckauftrag (ungerade Seiten) fehlgeschlagen."

SHEETS=$(( (PAGES + 1) / 2 ))
MSG="<b>Vorderseiten werden gedruckt ($SHEETS Blätter"
[ "$COPIES" -gt 1 ] && MSG="$MSG, $COPIES Exemplare"
MSG="$MSG).</b>\n\nWarte, bis alle Blätter gedruckt sind.\nDann den Stapel wieder ins Papierfach legen – so, dass die Rückseiten bedruckt werden."
if [ $((PAGES % 2)) -eq 1 ]; then
  MSG="$MSG\n\n<b>Achtung:</b> Das <b>letzte Blatt</b> (letzte Seite"
  [ "$COPIES" -gt 1 ] && MSG="$MSG des letzten Exemplars"
  MSG="$MSG) beiseitelegen, es bekommt keine Rückseite."
fi

zenity --question --title="$TITLE" --width=420 --text="$MSG" \
  --ok-label="Rückseiten drucken" --cancel-label="Abbrechen" || exit 0

# --- Durchgang 2: gerade Seiten --------------------------------------------
OPTS=(-o page-set=even)
[ "$REVERSE_EVEN" = "1" ] && OPTS+=(-o outputorder=reverse)

lp -d "$PRINTER" "${OPTS[@]}" -t "$NAME (Rückseiten)" "$PRINTFILE" >/dev/null \
  || fail "Druckauftrag (gerade Seiten) fehlgeschlagen."

notify-send -i printer "$TITLE" "Rückseiten werden gedruckt." 2>/dev/null
exit 0
