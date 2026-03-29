#!/usr/bin/env bash
# generate_icon_placeholder.sh
# Rosemount — App Icon Generator
#
# Regenerates all required App Icon sizes from the 1024x1024 source PNG
# using ImageMagick (brew install imagemagick).
#
# Usage:
#   chmod +x generate_icon_placeholder.sh
#   ./generate_icon_placeholder.sh
#
# Output: all PNGs are written to ../Resources/Assets.xcassets/AppIcon.appiconset/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SCRIPT_DIR}/../Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
OUT_DIR="${SCRIPT_DIR}/../Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v convert &>/dev/null; then
    echo "❌  ImageMagick not found. Install it with: brew install imagemagick"
    exit 1
fi

if [ ! -f "$SOURCE" ]; then
    echo "❌  Source icon not found at: $SOURCE"
    echo "    Place a 1024×1024 PNG at that path and re-run."
    exit 1
fi

echo "✅  Source icon: $SOURCE"

# Sizes required by Xcode / App Store Connect
declare -A SIZES=(
    ["AppIcon-20.png"]="20"
    ["AppIcon-29.png"]="29"
    ["AppIcon-38.png"]="38"
    ["AppIcon-40.png"]="40"
    ["AppIcon-58.png"]="58"
    ["AppIcon-60.png"]="60"
    ["AppIcon-76.png"]="76"
    ["AppIcon-87.png"]="87"
    ["AppIcon-114.png"]="114"
    ["AppIcon-120.png"]="120"
    ["AppIcon-152.png"]="152"
    ["AppIcon-167.png"]="167"
    ["AppIcon-180.png"]="180"
    ["AppIcon-1024.png"]="1024"
)

for FILENAME in "${!SIZES[@]}"; do
    SIZE="${SIZES[$FILENAME]}"
    OUTPUT="${OUT_DIR}/${FILENAME}"
    convert "$SOURCE" -resize "${SIZE}x${SIZE}" "$OUTPUT"
    echo "   → ${FILENAME} (${SIZE}×${SIZE})"
done

echo ""
echo "✅  All icon sizes generated in: $OUT_DIR"
