// Fetch the wallet balance over Nostr Wallet Connect (NIP-47) and print sats.
// The connection string is read from $NWC_URL, never from argv.
// Requires @getalby/sdk (npm i -g @getalby/sdk) and Node 22+ (global WebSocket).
import { nwc } from "@getalby/sdk";

const url = process.env.NWC_URL;
if (!url) process.exit(1);

const client = new nwc.NWCClient({ nostrWalletConnectUrl: url });
try {
  const res = await client.getBalance();   // NIP-47 returns msats
  const sats = Math.floor((res.balance ?? 0) / 1000);
  if (!Number.isFinite(sats)) process.exit(1);
  console.log(sats);
} catch {
  process.exit(1);
} finally {
  client.close?.();
}
process.exit(0);
