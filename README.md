# AutoCompounder

`AutoCompounder`is a Solidity smart contract deployed on the Binance Smart Chain (BSC) testnet. This contract automates the process of compounding rewards for users by interacting with other contracts such as the Wombat MasterChefV2, PoolV2, and PancakeSwap Router V3.

## Installation

To install`AutoCompounder`,  follow these steps:
- Clone this repository to your local machine
- Install dependencies by running `npm install`
- All the smart contracts in the `contracts` folder

## Running Tests
- Run hardhat test cases by running `npx hardhat test --network bscTestNet`

## About the Contract
The AutoCompounder contract has the following features:

- Minting faucet USDC for testing purposes (only callable by the contract owner).
- Depositing USDC to PoolV2 to receive USDC-LP tokens.
- Withdrawing USDC from PoolV2 using USDC-LP tokens.
- Staking LP tokens in MasterWombatV2 to earn rewards.
- Depositing and staking USDC in one function call.
- Checking pending WOM token rewards for a user.
- Checking the staked USDC-LP token amount of a user.
- Auto-compounding rewards by swapping WOM tokens to USDC, depositing USDC back to PoolV2 to get LP tokens, and staking those LP tokens in MasterWombatV2.

## Time Spent
- 5.19 10am to 6pm -> write smart contract and read the doc、analyze the verified smart contracts: 8 hours total
- 5.20 0am to 3am -> almost complete all the logic of the smart contract and test it using remix: 3 hours total
- 5.20 9am to 9pm -> write test cases to verify the whole process is correct or not, check contract security issues: 12 hours total
- total: 8 + 3 + 12 = 23 hours

## Improvements
If I had more time, I would improve the following aspects of the `AutoCompounder` contract:
- The deposit and withdraw function I will make these functions called by fallback function, because for some mev hackers, the will monitor 
this contract's pending transactions all the time, then decode the function input if they have the contract abi. If they can know who is going
to deposit or withdraw with a lot of money, they will insert their transactions before the user's transaction by using some mev tools such as 
flashbots. So if we can hide the input data by calling the fallback function and the function selector is contained in the input data, the mev
hackers are so hard to track who is going to deposit or withdraw.


- Try to use more efficient ways to swap wom token to usdc, cause in the current contract, I just swap it from pancake v3 wom-usdc 0.1% pool directly.
this will incur some serious problems such as Price Manipulation Attacks，So if we can use chainLink oracle price or some other tools to calculate the best
route to swap the token, I can make this contract more safe.


- Add more comprehensive tests to cover edge cases and potential vulnerabilities.


- Implement more error handling to prevent unexpected behavior and improve user experience.


- Add more documentation and comments to make the code more readable and understandable for other developers.


- Optimize gas usage to reduce transaction costs for users.

