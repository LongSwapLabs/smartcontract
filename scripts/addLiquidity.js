// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { parseUnits } = require("ethers");
const hre = require("hardhat");

async function main() {
  const instance = await hre.ethers.getContractAt(
    "X314",
    "0x003144B41d9743D402c5bdF3f72Ca0f327aA0Bca"
  );

  const tx = await instance.addLiquidity(37324000, { value: parseUnits("40", 18) });

  console.log(tx.hash);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
