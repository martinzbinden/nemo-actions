#!/bin/bash
# This script converts selected ODT files to PDF using LibreOffice

# Check if any files are selected
if [ "$#" -eq 0 ]; then
    zenity --error --text="No files selected."
    exit 1
fi

# Loop through each selected file
for file in "$@"; do
    # Check if the file is an ODT file
    if [[ "$file" == *.odt ]]; then
        # Get the directory and filename without extension
        dir=$(dirname "$file")
        filename=$(basename "$file" .odt)

        # Convert the ODT file to PDF using LibreOffice
        libreoffice --headless --convert-to pdf --outdir "$dir" "$file"
    fi
done

zenity --info --text="Conversion complete."
