# Omarchy Lightning balance widget

A bar widget for [Omarchy](https://omarchy.org) that shows your Lightning wallet
balance in sats, read-only. Built for the Omarchy 4.5 Quickshell bar.

It reads the balance over **Nostr Wallet Connect** (NIP-47) by default, so the
widget only ever needs a read-only connection — no spend access, no keys on the
machine beyond a get-balance connection string you control and can revoke.

## Install

```bash
git clone https://github.com/hasky00/omarchy-lightning-balance.git
cd omarchy-lightning-balance
./install.sh
```

Then edit `~/.config/omarchy/lightning/config` and paste your connection:

- **NWC (recommended):** in your wallet, create a connection scoped to
  `get_balance` only, and put its `nostr+walletconnect://…` string in `NWC_URL`.
- **Alby token (fallback):** set `PROVIDER=alby` and an `ALBY_TOKEN` with the
  balance read scope.

Keep that file private: `chmod 600 ~/.config/omarchy/lightning/config`.

Finally, add the **Lightning balance** widget to your bar (Appearance → the bar
widget list) and reload the shell.

## How it works

- `bin/omarchy-lightning-balance` — prints the balance in whole sats, or exits
  non-zero so the widget hides itself. The secret never appears in argv.
- `bin/nwc-balance.mjs` — fetches the balance over NIP-47 using `@getalby/sdk`.
- `plugins/lightning-balance/` — the Quickshell bar widget, refreshing every two
  minutes and on click.

## License

MIT © Hasky Labs, Copenhagen. All rights reserved.
