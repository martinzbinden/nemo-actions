# Nemo-Aktionen

Eigene Aktionen für den Dateimanager Nemo (Linux Mint). Installation: Repository nach
`~/.local/share/nemo/actions/` klonen, Skripte ausführbar lassen. Abhängigkeiten stehen
in der jeweiligen `.nemo_action`-Datei (`Dependencies=`).

| Aktion | Zweck |
|---|---|
| `rip-cd` | Audio-CD in den aktuellen Ordner rippen (Opus 128 kbit/s, `Interpret/Album/NN Titel.opus`, Tags per MusicBrainz, nur die Disc-ID wird gesendet). Rechtsklick auf freie Fläche im Ordner. Laufwerk über `CDDEV`, sonst `/dev/cdrom`. |
| `split-pdf` | PDF mit Seitenvorschau an frei wählbaren Stellen trennen |
| `xlsx-to-csv` | Excel: ein CSV pro Tabellenblatt |
| `images-to-pdf` | Bilder zu PDF (einzeln oder zusammen) |
| `manual-duplex` | PDF manuell beidseitig drucken |
| `webp_convert`, `convert_to_webp`, `pdf_*_to_webp` | WebP-Konvertierungen |
| `odt2pdf` | ODT-Dateien mit LibreOffice zu PDF |
| `print`, `pdf` | Dateien drucken (`lp -o fit-to-page`) |
| `create-pdf*` | PDF aus Bildern bzw. Dokumenten (unoconv) |
| `ocr-pdf` | **nicht funktionsfähig:** verweist auf ein fehlendes Skript |
