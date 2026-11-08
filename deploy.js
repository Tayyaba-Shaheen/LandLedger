/**
 * deploy.js — Hardhat deployment script for LandLedger
 * Deploys contract to Sepolia and seeds all 42 DHA Phase 1 plots
 *
 * Usage:
 *   npx hardhat run scripts/deploy.js --network sepolia
 *
 * Required in hardhat.config.js:
 *   networks: {
 *     sepolia: {
 *       url: "https://sepolia.infura.io/v3/YOUR_KEY",
 *       accounts: ["0xYOUR_PRIVATE_KEY"]
 *     }
 *   }
 */

const { ethers } = require("hardhat");

// ─────────────────────────────────────────────────────
//  PLOT SEED DATA — DHA Phase 1, Rawalpindi
//  Each entry: [plotId, block, size, marla, type, ownerAddress, notes]
//  Replace owner addresses with real Sepolia test wallets
// ─────────────────────────────────────────────────────
const OWNER = {
  alice:  "0xAliceAddress000000000000000000000000001",
  bob:    "0xBobAddress0000000000000000000000000002",
  carol:  "0xCarolAddress00000000000000000000000003",
  david:  "0xDavidAddress00000000000000000000000004",
  eve:    "0xEveAddress0000000000000000000000000005",
  faisal: "0xFaisalAddress0000000000000000000000006",
  gov:    "0xGovDHAAddress0000000000000000000000007",
};

// prettier-ignore
const PLOTS = [
  // Block A
  ["A-101","A","10 Marla",10,"Residential", OWNER.alice,  "Corner plot, road facing"],
  ["A-102","A","10 Marla",10,"Residential", OWNER.bob,    "Near park, excellent location"],
  ["A-103","A","5 Marla", 5, "Residential", OWNER.carol,  "Ready to build, utilities available"],
  ["A-104","A","5 Marla", 5, "Residential", OWNER.david,  ""],
  // Block B
  ["B-201","B","1 Kanal", 20,"Residential", OWNER.eve,    "1 Kanal, boundary wall done, prime corner"],
  ["B-202","B","10 Marla",10,"Residential", OWNER.faisal, ""],
  ["B-203","B","10 Marla",10,"Residential", OWNER.alice,  "Selling 5 Marla from south portion"],
  ["B-204","B","5 Marla", 5, "Residential", OWNER.gov,    "Reserved"],
  // Block C
  ["C-301","C","10 Marla",10,"Commercial",  OWNER.bob,    "Commercial zoning, high foot traffic road"],
  ["C-302","C","5 Marla", 5, "Residential", OWNER.carol,  ""],
  ["C-303","C","5 Marla", 5, "Residential", OWNER.david,  "Near mosque, peaceful area"],
  ["C-304","C","2 Kanal", 40,"Commercial",  OWNER.eve,    "Large commercial plot"],
  // Block D
  ["D-401","D","10 Marla",10,"Residential", OWNER.faisal, ""],
  ["D-402","D","10 Marla",10,"Residential", OWNER.alice,  "Double road, north facing"],
  ["D-403","D","5 Marla", 5, "Residential", OWNER.bob,    ""],
  ["D-404","D","5 Marla", 5, "Residential", OWNER.carol,  "Ideal for small family home"],
  // Block E
  ["E-501","E","1 Kanal", 20,"Residential", OWNER.david,  "Built house on it"],
  ["E-502","E","10 Marla",10,"Residential", OWNER.eve,    "Plot + foundation laid"],
  ["E-503","E","5 Marla", 5, "Residential", OWNER.faisal, "Selling half — east portion"],
  ["E-504","E","5 Marla", 5, "Residential", OWNER.alice,  ""],
  // Block F
  ["F-601","F","1 Kanal", 20,"Residential", OWNER.bob,    "1 Kanal — best block F location, park-facing"],
  ["F-602","F","10 Marla",10,"Residential", OWNER.carol,  ""],
  ["F-603","F","10 Marla",10,"Residential", OWNER.david,  "South-facing, ideal orientation"],
  ["F-604","F","5 Marla", 5, "Residential", OWNER.eve,    ""],
];

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying LandLedger with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH\n");

  // Deploy
  const LandLedger = await ethers.getContractFactory("LandLedger");
  const contract = await LandLedger.deploy();
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  console.log("✅ LandLedger deployed to:", address);
  console.log("   Explorer: https://sepolia.etherscan.io/address/" + address + "\n");

  // Seed plots
  console.log(`Seeding ${PLOTS.length} plots…`);
  for (const [plotId, block_, size, marla, type_, owner, notes] of PLOTS) {
    const tx = await contract.registerPlot(plotId, block_, size, marla, type_, owner, notes);
    await tx.wait();
    process.stdout.write(`  ✓ ${plotId}\r`);
  }
  console.log(`\n✅ All ${PLOTS.length} plots registered on-chain.\n`);

  console.log("─────────────────────────────────");
  console.log("CONTRACT ADDRESS:", address);
  console.log("NETWORK:          Sepolia Testnet");
  console.log("ADMIN:           ", deployer.address);
  console.log("─────────────────────────────────");
  console.log("\nNext: paste the CONTRACT_ADDRESS into landledger.html");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
