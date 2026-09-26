#!/usr/bin/env bash
# make_tarball.sh — generate a clean shareable tarball of PlasticWeights
#
# Usage:
#   ./scripts/make_tarball.sh              # outputs PlasticWeights_<timestamp>.tar.gz
#   ./scripts/make_tarball.sh my_name.tar.gz  # custom output name
#
# Excludes: .git, .gitignore, __pycache__, .pyc, .DS_Store, and any existing tarballs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="PlasticWeights"

if [[ $# -ge 1 ]]; then
    OUTPUT="$1"
else
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    OUTPUT="${PROJECT_DIR}/${PROJECT_NAME}_${TIMESTAMP}.tar.gz"
fi

INCLUDE_ITEMS=(
    Project.toml
    Manifest.toml
    README.md
    docs
    scripts
    spec
    src
    test
)

EXCLUDES=(
    --exclude='.git'
    --exclude='.gitignore'
    --exclude='.DS_Store'
    --exclude='__pycache__'
    --exclude='*.pyc'
    --exclude='*.tar.gz'
    --exclude='*.tar.bz2'
)

# Build the tar arguments: transform each item to sit under PlasticWeights/
TRANSFORM="s|^|${PROJECT_NAME}/|"

cd "$PROJECT_DIR"

tar -czf "$OUTPUT" \
    "${EXCLUDES[@]}" \
    --transform "$TRANSFORM" \
    "${INCLUDE_ITEMS[@]}"

SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo "Created: $OUTPUT ($SIZE)"
