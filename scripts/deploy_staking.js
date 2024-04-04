// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();

  const Staking = await hre.ethers.getContractFactory("Staking");

  console.log("Deploying...");

  const token = '0x003144B41d9743D402c5bdF3f72Ca0f327aA0Bca';

  const instance = await hre.upgrades.deployProxy(Staking, [token]);
  await instance.waitForDeployment();

  console.log(
    `deployed to`, instance.target
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
