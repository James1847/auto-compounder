// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/TestERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPoolV2.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IMasterWombatV2.sol";

contract AutoCompounder is Ownable, ReentrancyGuard {
    address public constant pancakeSwapRouter = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // PancakeSwap Router V3 on BSC testnet
    address public constant womMasterChefV2Address = 0x1b97eF873A44497Be1E0Ec9178ECBA99E7EAdC26; // Wombat MasterChefV2 on BSC testnet  !!!!!!!!!(0x8dDB990C0489338b73bB9fFEa19A2f7f6bcc7c4f)
    address public constant poolV2ProxyAddress = 0x0078423B8E3b02768d708C1E92a115bf478347Df;
    address public constant lpTokenUSDCAddress = 0xA55741C7002FBdA046B0E8BC5e0D126f911Fa334; // Wombat Exchange Main pool’s LP-USDC on BSC testnet
    address public constant _usdc = 0x38dBDc4aa4D506CCDda88A08C3EdFf0a2636C2A5; // usdc token address on BSC testnet
    address public constant _wom = 0xeCa80fd2B6902C5447cC067f3d3Ce2670c50eB7E; // wom token address on BSC testnet
    mapping(address => uint256) public depositedAmount;
    mapping(address => uint256) public depositedLpRewards;
    IPoolV2 public poolV2 = IPoolV2(poolV2ProxyAddress);
    IMasterWombatV2 public masterWombatV2 = IMasterWombatV2(womMasterChefV2Address);
    TestERC20 public usdc = TestERC20(_usdc);
    IERC20 public wom = IERC20(_wom);
    IERC20 public usdcLP = IERC20(lpTokenUSDCAddress);

    event Deposit(uint256 amount, uint256 lpReward);
    event Stake(uint256 amount, address receiver);
    event MintedFaucetUSDC(uint256 amount);

    constructor() {
    }

    function mintFaucetUSDC(uint256 _amount) external onlyOwner {
        usdc.faucet(_amount);
        usdc.transfer(msg.sender, _amount);
        emit MintedFaucetUSDC(_amount);
    }


    function depositToPool(uint256 _amount, uint256 _deadline) internal returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        usdc.transferFrom(msg.sender, address(this), _amount);
        depositedAmount[msg.sender] += _amount;
        usdc.approve(poolV2ProxyAddress, _amount);
        uint256 lpReward = poolV2.deposit(_usdc, _amount, 0, address(this), _deadline, false);
        require(lpReward > 0, "lp token has been exploited");
        depositedLpRewards[msg.sender] += lpReward;
        emit Deposit(_amount, lpReward);
        return depositedLpRewards[msg.sender];
    }

    function stakeToMasterWombat(uint256 _lpReward, address receiver) internal {
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        require(_pid >= 0, "pool info not added to masterwombat, please contact admin");
        usdcLP.approve(address(masterWombatV2), _lpReward);
        masterWombatV2.deposit(_pid, _lpReward);
        depositedLpRewards[msg.sender] -= _lpReward;
        emit Stake(_lpReward, receiver);
    }


    function depositAndStake(uint256 _amount, uint256 _deadline) external {
        uint256 lpReward = depositToPool(_amount, _deadline);
        require(lpReward > 0, "deposit failed");
        stakeToMasterWombat(lpReward, msg.sender);
    }

    function getDepositedAmount(address _user) external view returns (uint256) {
        return depositedAmount[_user];
    }

    function getDepositedAmountFromPoolV2(address _user) external view returns (uint256) {
        return depositedLpRewards[_user];
    }

    function autoCompound() external nonReentrant returns (uint256 harvest, uint256 deposited) {
        // get pending VOM
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        require(_pid >= 0, "pool info not added to masterwombat, please contact admin");
        (harvest, , , ) = masterWombatV2.pendingTokens(_pid, address(this));

        require(harvest > 0, "Nothing to compound");
        // run deposit with amount 0
        masterWombatV2.deposit(_pid, 0);

        // should add checking for value before and after running deposit for
        // emit Claim(user, harvest);

        // swap from wom to USDC
        usdc.approve(address(pancakeSwapRouter), harvest);

        uint256 amountOut = swap(harvest);

        // deposit again
        deposited = deposit(amountOut, 0, user, 0);
        emit AutoCompound(msg.sender, user, harvest, deposited);
    }
}