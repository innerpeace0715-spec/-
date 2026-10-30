#!/usr/bin/env bash
# Build FilmCraft's web (WebAssembly) app from vendor/filmcraft and put it
# where the U-file page loads it: public/filmcraft/ (bundled into dist/ and
# the APK by `npm run build`).
#
# Needs: the Rust toolchain in vendor/filmcraft/rust-toolchain.toml (with the
# wasm32-unknown-unknown target) and wasm-bindgen-cli 0.2.129
# (cargo install wasm-bindgen-cli --version 0.2.129 --locked).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/vendor/filmcraft"
cargo xtask web
rm -rf "$root/public/filmcraft"
mkdir -p "$root/public/filmcraft"
cp -R "${CARGO_TARGET_DIR:-target}/web/dist/." "$root/public/filmcraft/"
echo "FilmCraft web build copied to public/filmcraft"
