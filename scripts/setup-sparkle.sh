#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
sparkle_dir=".runtime/sparkle/$version"
if [ -f "$sparkle_dir/.verified" ] && [ "$(cat "$sparkle_dir/.verified")" = "$checksum" ]; then
  exit 0
fi
mkdir -p .runtime/sparkle
staging=$(mktemp -d .runtime/sparkle/download.XXXXXX)
trap 'rm -rf "$staging"' EXIT
curl -fL --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$staging/archive.tar.xz"
printf '%s  %s\n' "$checksum" "$staging/archive.tar.xz" | shasum -a 256 -c -
tar -xJf "$staging/archive.tar.xz" -C "$staging"
rm "$staging/archive.tar.xz"
printf '%s\n' "$checksum" > "$staging/.verified"
rm -rf "$sparkle_dir"
mv "$staging" "$sparkle_dir"
