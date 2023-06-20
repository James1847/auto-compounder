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
    event Withdraw(uint256 amountOut, address to);
    event Claim(address indexed claimFor, uint256 reward);
    event AutoCompound(address indexed user,uint256 harvest,uint256 redeposit);
    event Swap(address receiver, uint256 amountIn, uint256 amountOut);

    constructor() {
    }

    // easy way to mint faucet usdc
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

    // cause MasterWombatV2 contract can only withdraw lp tokens to msg.sender by calling the withdraw function
    // if we try to withdraw lp tokens from smart contract the msg.sender will be address(this), the amount to be withdraw will always be zero
    // so user have to withdraw lp tokens by directly calling the MasterWombatV2 contract's withdraw function
    // then user will call withdrawFromPool of this contract to withdraw his USDC by sending his lp tokens to this contract
    function withdrawFromPool(uint256 _amount, uint256 _minimumAmountOut, uint256 _deadline) external returns (uint256) {
        // transfer usdc lp token from user to this contract
        usdcLP.transferFrom(msg.sender, address(this), _amount);

        //approve usdcLP can be consumed by poolV2 contract
        usdcLP.approve(address(poolV2), _amount);
        // try to withdraw USDC using lp token then send to msg.sender directly
        uint256 withdrawAmount = poolV2.withdraw(address(usdc), _amount, _minimumAmountOut, msg.sender, _deadline);
        emit Withdraw(withdrawAmount, msg.sender);
        return withdrawAmount;

    }

    // stake usdc lp token to MasterWombatV2
    function stakeToMasterWombat(uint256 _lpReward) internal {
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        usdcLP.approve(address(masterWombatV2), _lpReward);
        masterWombatV2.depositFor(_pid, _lpReward, msg.sender);
        emit Stake(_lpReward, msg.sender);
    }

    // 1\ deposit usdc to poolV2 to get lpToken
    // 2\ stake lpToken to MasterWombatV2
    function depositAndStake(uint256 _amount, uint256 _deadline) public returns (uint256) {
        uint256 lpReward = depositToPool(_amount, _deadline);
        require(lpReward > 0, "deposit failed");
        stakeToMasterWombat(lpReward);
        return lpReward;
    }

    // get the amount of pending wom rewards from masterWombatV2
    function getPendingWom(address _user) public view returns (uint256) {
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        (uint256 pendingWomAmount, , ,) = masterWombatV2.pendingTokens(_pid, _user);
        return pendingWomAmount;
    }

    // get staked lp token amount of user
    function getStakedLp(address _user) public view returns (uint128) {
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        (uint128 stakedLp,,,) = masterWombatV2.userInfo(_pid, _user);
        return stakedLp;
    }

    // autoCompound will first check the balance of pending wom token to be withdraw
    // if the amount of pending wom token is zero, then return zero
    // 1\ otherwise the contract will first harvest the pending wom tokens:                WOM: masterWombatV2 -> msg.sender
    // 2\ then transfer the pending amount of wom token from msg.sender to this contract:   WOM: msg.sender -> address(this)
    // 3\ then swap wom token to usdc and send usdc to msg.sender :                        WOM -> USDC -> USDC: msg.sender -> address(this)
    // 4\ finally depositAndStake Again:                                                   USDC -> USDCLP -> masterWombatV2
    // notice we have to make sure user have already approve the enough amount of USDC and WOM tokens to our contract, this process will be handled by frontend
    function autoCompound() external nonReentrant returns (uint256) {
        // get wom token allowance from user to this contract
        uint256 womAllowance = wom.allowance(msg.sender, address(this));
        // get pool id of lp token
        uint256 _pid = masterWombatV2.getAssetPid(lpTokenUSDCAddress);
        // get pending wom token amount to be harvested
        (uint256 pendingWomAmount, , ,) = masterWombatV2.pendingTokens(_pid, msg.sender);
        if (pendingWomAmount == 0) {
            return 0;
        }
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

    // swap wom token to usdc, we will use pancakeswap v3 router contract directly
    // actually pancakeswap v3 router contract is forked from uniswap v3 router2 contract
    function swapFromPancakeV3(uint256 amountIn) internal nonReentrant returns (uint256 amountOut) {
        wom.approve(address(pancakeSwapRouter), amountIn);
        // based on the task we have to swap tokens on PancakeSwap V3 WOM-USDC pool, which pool fee is 100 (0.1%)
        uint24 poolFee = 100;
        // @todo: if we want swap as much amountOut as possible, maybe we have to get the best route from pancakeswap alpha router
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