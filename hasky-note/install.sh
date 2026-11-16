#!/usr/bin/env bash
# Hasky Note installer for Omarchy
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v cargo >/dev/null; then
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "Rust is missing. Install it first: brew install rust"
    exit 1
  fi
  echo "Installing Rust..."
  sudo pacman -S --needed --noconfirm rust
fi

echo "Building Hasky Note..."
cargo build --release
mkdir -p ~/.local/bin ~/notes
install -m 755 target/release/hasky-note ~/.local/bin/hasky-note

# macOS: no Hyprland, just the command
if [[ "$(uname)" == "Darwin" ]]; then
  echo "Done. Run: hasky-note  (make sure ~/.local/bin is in your PATH)"
  exit 0
fi

# Hotkey + floating window rules live in their own file
HYPR=~/.config/hypr
cp hypr/hasky-note.conf "$HYPR/hasky-note.conf"
if ! grep -q "hasky-note.conf" "$HYPR/hyprland.conf"; then
  printf '\n# Hasky Note\nsource = ~/.config/hypr/hasky-note.conf\n' >> "$HYPR/hyprland.conf"
fi

hyprctl reload >/dev/null 2>&1 || true
echo "Done. Press Super + Alt + N to open Hasky Note."
