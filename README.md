# LandLedger — Deployment Guide
## DHA Phase 1, Rawalpindi · Sepolia Testnet

---

## Files

| File | Purpose |
|------|---------|
| `LandLedger.sol` | Main Solidity smart contract |
| `deploy.js` | Hardhat deployment + plot seeding script |
| `LandLedger.abi.json` | Contract ABI for frontend integration |
| `landledger.html` | Frontend (connect to contract address below) |

---

## Quick Deploy (Remix — easiest for semester project)

1. Go to **https://remix.ethereum.org**
2. Create new file → paste `LandLedger.sol`
3. Compile tab → Compiler **0.8.19** → Compile
4. Deploy tab → Environment: **Injected Provider (MetaMask)**
5. Make sure MetaMask is on **Sepolia** testnet
6. Click **Deploy** → Confirm in MetaMask
7. Copy the deployed contract address
8. Paste it into `landledger.html` at the `CONTRACT_ADDRESS` constant

---

## Deploy via Hardhat

```bash
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npx hardhat init

# Add to hardhat.config.js:
# networks: { sepolia: { url: "...", accounts: ["0xPRIVATE_KEY"] } }

# Edit deploy.js: replace OWNER addresses with your real Sepolia wallets

npx hardhat run scripts/deploy.js --network sepolia
```

---

## Contract Functions Reference

### Admin Only
| Function | Description |
|----------|-------------|
| `registerPlot(...)` | Register a new plot (called at deploy time) |
| `authorityTransfer(plotId, newOwner, reason)` | Forced transfer (inheritance, court) |
| `withdrawFees()` | Withdraw collected platform fees |
| `setFeeBps(bps)` | Set platform fee (max 10%) |
| `transferAdmin(addr)` | Hand over admin role |

### Plot Owner
| Function | Description |
|----------|-------------|
| `listForSale(plotId, priceWei, partialPct)` | List full or partial plot (25/50/75/100%) |
| `delistPlot(plotId)` | Remove listing |
| `updateNotes(plotId, notes)` | Update seller notes |

### Buyer (payable)
| Function | Description |
|----------|-------------|
| `buyPlot(plotId)` | Purchase listed plot, send ETH with call |

### Read (free)
| Function | Returns |
|----------|---------|
| `getPlot(plotId)` | Full Plot struct |
| `getHistory(plotId)` | Array of TransferRecord |
| `getOwnerPlots(address)` | Array of plotIds |
| `getListing(plotId)` | Active listing details |
| `getAllPlotIds()` | All registered plot IDs |
| `totalPlots()` | Count |

---

## Partial Plot Sale (Key Feature)

When a 10 Marla owner sells 50%:
- `listForSale("B-203", priceInWei, 50)`
- Buyer calls `buyPlot("B-203")` with the ETH
- Contract creates new plot `"B-203-S"` (5 Marla) → buyer
- Original `"B-203"` updated to 5 Marla → seller retains

---

## Platform Fee

Default: **2%** (200 basis points)  
Fee is deducted from each sale and sent to the admin wallet.  
Admin can change with `setFeeBps()`, max 10%.

---

## Connecting Frontend (landledger.html)

Find this line in the HTML file and paste your deployed address:

```js
const CONTRACT_ADDRESS = "0xYOUR_DEPLOYED_ADDRESS_HERE";
```

And paste the ABI from `LandLedger.abi.json` into:

```js
const CONTRACT_ABI = [ /* paste here */ ];
```

The HTML already uses `window.ethereum` (MetaMask) and `ethers.js` via CDN.
