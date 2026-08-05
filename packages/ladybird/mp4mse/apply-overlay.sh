#!/usr/bin/env bash
# Apply MP4/fMP4 MSE overlay into a Ladybird source tree.
#
# OUTLINE ONLY: no parser sources are shipped yet. See README.md milestones
# (M0–M4). This script will grow as files land under this directory.
set -euo pipefail

overlay_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ladybird_root="${1:?usage: apply-overlay.sh /path/to/ladybird}"

if [[ ! -d "$ladybird_root/Libraries/LibWeb/MediaSourceExtensions" ]]; then
  echo "error: $ladybird_root does not look like a Ladybird checkout" >&2
  exit 1
fi

# Planned installs (uncomment / extend as M0+ lands):
#   Libraries/LibWeb/MediaSourceExtensions/MP4ByteStreamParser.{h,cpp}
#   Libraries/LibWeb/MediaSourceExtensions/Isobmff/*
# Planned patches:
#   MediaSource.cpp          — is_type_supported for video/mp4 + avc1/mp4a
#   SourceBuffer.cpp         — make<MP4ByteStreamParser>() for subtype mp4
#   Libraries/LibWeb/CMakeLists.txt — add MP4ByteStreamParser.cpp

if [[ ! -f "$overlay_root/Libraries/LibWeb/MediaSourceExtensions/MP4ByteStreamParser.cpp" ]]; then
  echo "error: mp4mse overlay is outline-only (no MP4ByteStreamParser.cpp yet)." >&2
  echo "       See $overlay_root/README.md" >&2
  exit 1
fi

echo "mp4mse overlay applied to $ladybird_root"
