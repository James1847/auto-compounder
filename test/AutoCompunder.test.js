const {expect} = require("chai");
const {ethers} = require("hardhat");

describe("AutoCompounder", function () {
    let AutoCompounder, autoCompounder, owner, addr1, addr2, usdcContract, womContract, masterWombatV2Contract,
        usdcLpContract;

    before(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        AutoCompounder = await ethers.getContractFactory("AutoCompounder", {signer: owner});
        autoCompounder = await AutoCompounder.deploy();
        await autoCompounder.deployed();
        console.log("Deploy contracts with the account:", owner.address, "addr1: ", addr1.address, "autoCompounder: ", autoCompounder.address);
        usdcContract = await ethers.getContractAt("TestERC20", "0x38dBDc4aa4D506CCDda88A08C3EdFf0a2636C2A5");
        womContract = await ethers.getContractAt("IERC20", "0xeCa80fd2B6902C5447cC067f3d3Ce2670c50eB7E");
        masterWombatV2Contract = await ethers.getContractAt("IMasterWombatV2", "0x1b97eF873A44497Be1E0Ec9178ECBA99E7EAdC26");
        usdcLpContract = await ethers.getContractAt("IERC20", "0xA55741C7002FBdA046B0E8BC5e0D126f911Fa334");
        const amount = ethers.utils.parseUnits("9999999", 18);
        // Approve AutoCompounder to spend addr1's USDC
        await usdcContract.connect(addr1).approve(autoCompounder.address, amount);
        await womContract.connect(addr1).approve(autoCompounder.address, amount);
        await usdcLpContract.connect(addr1).approve(autoCompounder.address, amount);
    });

    describe("Depositing and staking USDC", function () {

        it("Should deposit USDC to PoolV2 and receive LP tokens", async () =>  {
            const depositAmount = ethers.utils.parseUnits("1", 18);
            const deadline = parseInt((new Date().getTime() / 1000)) + 1200
            console.log("deadline: ", deadline);
            await autoCompounder.connect(addr1).depositAndStake(depositAmount, deadline);
            // Check if addr1 staked LP tokens
            expect(await autoCompounder.connect(addr1).getStakedLp(addr1.address)).to.gte(ethers.BigNumber.from(0));
        });
    });

    describe("Auto-compounding rewards", function () {

        it("Should auto-compound rewards and increase LP token stake", async () =>  {
            // auto compound for addr1
            // const depositAmount = ethers.utils.parseUnits("99999", 18);
            // await womContract.connect(addr1).approve(autoCompounder.address, depositAmount);
            const initialStake = await autoCompounder.connect(addr1).getStakedLp(addr1.address);

            await autoCompounder.connect(addr1).autoCompound({gasLimit: 5000000});

            const finalStake = await autoCompounder.connect(addr1).getStakedLp(addr1.address);
            expect(finalStake).to.be.gte(initialStake);
        });
    });

    describe("withdraw rewards", function () {

        it("Should able to withdraw usdc lp token from masterWombat", async () => {
            const depositedLpAmountBefore = await autoCompounder.connect(addr1).getStakedLp(addr1.address);
            expect(depositedLpAmountBefore).to.be.gt(0);
            const pid = await masterWombatV2Contract.connect(addr1).getAssetPid(usdcLpContract.address);
            await masterWombatV2Contract.connect(addr1).withdraw(pid, depositedLpAmountBefore);
            const depositedLpAmountAfter = await autoCompounder.connect(addr1).getStakedLp(addr1.address);
            console.log("pid: ", pid, "depositedLpAmountBefore: ", depositedLpAmountBefore, "depositedLpAmountAfter: ", depositedLpAmountAfter)
            expect(depositedLpAmountBefore).to.be.gte(depositedLpAmountAfter);
        })

        it("should able to withdraw usdc token from poolV2", async () => {
            // await usdcLpContract.connect(addr1).approve(autoCompounder.address, ethers.utils.parseUnits("99999", 18));
            const usdcLpTokenBalance = await usdcLpContract.connect(addr1).balanceOf(addr1.address);
            const usdcBalanceBefore = await usdcContract.connect(addr1).balanceOf(addr1.address);
            const deadline = parseInt((new Date().getTime() / 1000)) + 120
            const tx = await autoCompounder.connect(addr1).withdrawFromPool(usdcLpTokenBalance, 0, deadline, {gasLimit: 5000000});
            await tx.wait();
            const usdcBalanceAfter = await usdcContract.connect(addr1).balanceOf(addr1.address);
            console.log("usdcBalanceBefore: ", usdcBalanceBefore, "usdcBalanceAfter: ", usdcBalanceAfter);
            expect(usdcBalanceAfter).to.be.gte(usdcBalanceBefore);
        })

    })


});
