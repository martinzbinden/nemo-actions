#!/bin/bash

IN=$*
date -R > ~/.local/share/nemo/actions/print.log
IFS=";" read -ra FILES <<< "$IN"
for i in "${FILES[@]}"; do
 echo "processing $i" >> ~/.local/share/nemo/actions/print.log
 lp -o fit-to-page "$i"
done
