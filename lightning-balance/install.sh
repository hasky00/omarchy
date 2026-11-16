#!/bin/bash
# Installs the Lightning balance bar widget for Omarchy into the current user's
# config. Safe to re-run. Does not touch any existing Omarchy files.
set -euo pipefail

src="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/lightning-balance"
bin_dir="$HOME/.local/bin"
cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/lightning"

mkdir -p "$plugin_dir" "$bin_dir" "$cfg_dir"
install -m 0644 "$src/plugins/lightning-balance/manifest.json" "$plugin_dir/manifest.json"
install -m 0644 "$src/plugins/lightning-balance/LightningBalance.qml" "$plugin_dir/LightningBalance.qml"
install -m 0755 "$src/bin/omarchy-lightning-balance" "$bin_dir/omarchy-lightning-balance"
install -m 0644 "$src/bin/nwc-balance.mjs" "$bin_dir/nwc-balance.mjs"

if [[ ! -e "$cfg_dir/config" ]]; then
  install -m 0600 "$src/config.example" "$cfg_dir/config"
  echo "Wrote $cfg_dir/config (edit it and paste your connection)."
else
  echo "Kept existing $cfg_dir/config."
fi

# NWC needs the Alby SDK available to node.
if [[ "$(grep -s '^PROVIDER=' "$cfg_dir/config" | head -1)" == "PROVIDER=nwc" ]]; then
  command -v node >/dev/null || echo "Note: node not found; install it for NWC mode."
  node -e "require('@getalby/sdk')" 2>/dev/null || {
    echo "Installing @getalby/sdk ..."
    npm install -g @getalby/sdk >/dev/null 2>&1 || echo "Could not install @getalby/sdk; run: npm install -g @getalby/sdk"
  }
fi

echo "Done. Add the 'Lightning balance' widget to your bar and reload the shell."
