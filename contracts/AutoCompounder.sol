// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/TestERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPoolV2.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IMasterWombatV2.sol";
import "./interfaces/IV3SwapRouter.sol";

contract AutoCompounder is Ownable, ReentrancyGuard {
    address public constant pancakeSwapRouterAddress = 0x9a489505a00cE272eAa5e07Dba6491314CaE3796; // PancakeSwap Router V3 on BSC testnet
    address public constant womMasterChefV2Address = 0x1b97eF873A44497Be1E0Ec9178ECBA99E7EAdC26; // Wombat MasterChefV2 on BSC testnet  !!!!!!!!!(0x8dDB990C0489338b73bB9fFEa19A2f7f6bcc7c4f)
    address public constant poolV2ProxyAddress = 0x0078423B8E3b02768d708C1E92a115bf478347Df;
    address public constant lpTokenUSDCAddress = 0xA55741C7002FBdA046B0E8BC5e0D126f911Fa334; // Wombat Exchange Main pool’s LP-USDC on BSC testnet
    address public constant _usdc = 0x38dBDc4aa4D506CCDda88A08C3EdFf0a2636C2A5; // usdc token address on BSC testnet
    address public constant _wom = 0xeCa80fd2B6902C5447cC067f3d3Ce2670c50eB7E; // wom token address on BSC testnet
    mapping(address => uint256) public depositedAmount;
    IPoolV2 public poolV2 = IPoolV2(poolV2ProxyAddress);
    IMasterWombatV2 public masterWombatV2 = IMasterWombatV2(womMasterChefV2Address);
    TestERC20 public usdc = TestERC20(_usdc);
    IERC20 public wom = IERC20(_wom);
    IERC20 public usdcLP = IERC20(lpTokenUSDCAddress);
    IV3SwapRouter public pancakeSwapRouter = IV3SwapRouter(pancakeSwapRouterAddress);

    event Deposit(uint256 amount, uint256 lpReward);
    event Stake(uint256 amount, address receiver);
    event MintedFaucetUSDC(uint256 amount);
    event Withdraw();
    event Claim(address indexed claimFor, uint256 reward);

    ///  An event thats emitted when a autoCompound is made to Pool
    event AutoCompound(
        address indexed user,
        uint256 harvest,
        uint256 redeposit
    );
    event Swap(address receiver, uint256 amountIn, uint256 amountOut);

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
        usdc.approve(poolV2ProxyAddress, _amount);
        uint256 lpReward = poolV2.deposit(_usdc, _amount, 0, address(this), _deadline, false);
        require(lpReward > 0, "lp token has been exploited");
        emit Deposit(_amount, lpReward);
        return lpReward;
    }

    function stakeToMasterWombat(uint256 _lpReward) internal {
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);

        usdcLP.approve(address(masterWombatV2), _lpReward);
        masterWombatV2.depositFor(_pid, _lpReward, msg.sender);
        emit Stake(_lpReward, msg.sender);
    }


    function depositAndStake(uint256 _amount, uint256 _deadline) public returns (uint256) {
        uint256 lpReward = depositToPool(_amount, _deadline);
        require(lpReward > 0, "deposit failed");
        stakeToMasterWombat(lpReward);
        return lpReward;
    }

    function getDepositedAmount(address _user) external view returns (uint256) {
        return depositedAmount[_user];
    }

    function getPendingWom(address _user) public view returns (uint256) {
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        (uint256 pendingWomAmount, , ,) = masterWombatV2.pendingTokens(_pid, _user);
        return pendingWomAmount;
    }

    function autoCompound() external nonReentrant returns (uint256) {
        // get wom token allowance from user to this contract
        uint256 womAllowance = wom.allowance(msg.sender, address(this));
        // get pool id of lp token
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        // get pending wom token amount to be harvested
        (uint256 pendingWomAmount, , ,) = masterWombatV2.pendingTokens(_pid, msg.sender);
        require(pendingWomAmount > 0, "Nothing to compound");
        // check if wom allowance is enough
        require(womAllowance >= pendingWomAmount, "Not enough allowance for wom token");
        // run depositFor with amount 0, just to harvest
        masterWombatV2.depositFor(_pid, 0, msg.sender);
        // transfer wom token from user to this contract, because the depositFor function will transfer wom token to msg.sender
        wom.transferFrom(msg.sender, address(this), pendingWomAmount);
        // get token amount out from swap
        uint256 amountOutUSDC = swapFromPancakeV3(pendingWomAmount);
        uint256 usdcAllowance = usdc.allowance(msg.sender, address(this));
        require(usdcAllowance >= amountOutUSDC, "Not enough allowance for usdc token");
        // deposit again
        usdc.transferFrom(msg.sender, address(this), amountOutUSDC);
        uint256 deposited = depositAndStake(amountOutUSDC, block.timestamp + 100);
        emit AutoCompound(msg.sender, pendingWomAmount, deposited);
        return deposited;
    }


    function swapFromPancakeV3(uint256 amountIn) internal nonReentrant returns (uint256 amountOut) {
        wom.approve(address(pancakeSwapRouter), amountIn);
        uint24 poolFee = 100;
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(wom),
            tokenOut: address(usdc),
            fee: poolFee,
            recipient: msg.sender,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        amountOut = pancakeSwapRouter.exactInputSingle(params);
        emit Swap(address(this), amountIn, amountOut);
    }
}