require("@nomicfoundation/hardhat-toolbox");


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.7",
  networks: {
    bscTestNet: {
      chainId: 97,
      accounts: ["c3b148548712b16e3b27f4ec9fa5b749a3550152e04cb6cc762719e9d5bc996d", "0e776e6cb0f21b6c167098f53c0cb01267c2cd213d7523d1539ffcc77255f124", "d2abd8f35e20faac00e794a994a64d85ca628092db12ef06cbcac3c6f7cd574f"],
      url: "https://data-seed-prebsc-1-s1.binance.org:8545"
    }
  },
};
