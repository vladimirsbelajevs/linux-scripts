#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob nocaseglob

echo "Convert TIF/TIFF to PNG"
echo "Preserve alpha channel? (y/n)"
read -r preserve_alpha

files=( *.tif *.tiff )

if (( ${#files[@]} == 0 )); then
  echo "No .tif/.tiff files found in: $(pwd)"
  exit 0
fi

for f in "${files[@]}"; do
  out="${f%.*}.png"
  echo "Converting: $f -> $out"

  if [[ "$preserve_alpha" =~ ^[Yy]$ ]]; then
    magick "$f" \
      -auto-orient \
      -alpha on \
      -colorspace sRGB \
      -depth 8 \
      -define png:color-type=6 \
      "$out"
  else
    magick "$f" \
      -auto-orient \
      -alpha off \
      -colorspace sRGB \
      -depth 8 \
      -define png:color-type=2 \
      "$out"
  fi
done

echo "Done."
