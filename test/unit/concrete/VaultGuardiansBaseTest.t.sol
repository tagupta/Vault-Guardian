// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../../Base.t.sol";
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
import {IERC20} from "../../../src/protocol/VaultGuardians.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {VaultGuardiansBase} from "../../../src/protocol/VaultGuardiansBase.sol";

import {VaultGuardians} from "../../../src/protocol/VaultGuardians.sol";
import {VaultGuardianGovernor} from "../../../src/dao/VaultGuardianGovernor.sol";
import {VaultGuardianToken} from "../../../src/dao/VaultGuardianToken.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import {UniswapAdapter} from 'src/protocol/investableUniverseAdapters/UniswapAdapter.sol';

contract VaultGuardiansBaseTest is Base_Test {
    address public guardian = makeAddr("guardian");
    address public user = makeAddr("user");

    VaultShares public wethVaultShares;
    VaultShares public usdcVaultShares;
    VaultShares public linkVaultShares;

    uint256 guardianAndDaoCut;
    uint256 stakePrice;
    uint256 mintAmount = 100 ether;

    // 500 hold, 250 uniswap, 250 aave
    AllocationData allocationData = AllocationData(500, 250, 250);
    AllocationData newAllocationData = AllocationData(0, 500, 500);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event GuardianAdded(address guardianAddress, IERC20 token);
    event GaurdianRemoved(address guardianAddress, IERC20 token);
    event InvestedInGuardian(address guardianAddress, IERC20 token, uint256 amount);
    event DinvestedFromGuardian(address guardianAddress, IERC20 token, uint256 amount);
    event GuardianUpdatedHoldingAllocation(address guardianAddress, IERC20 token);
    event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);


    function setUp() public override {
        Base_Test.setUp();
        guardianAndDaoCut = vaultGuardians.getGuardianAndDaoCut();
        stakePrice = vaultGuardians.getGuardianStakePrice();
    }

    function testDefaultsToNonFork() public view {
        assert(block.chainid != 1);
    }

    function testSetupAddsTokensAndPools() public {
        assertEq(vaultGuardians.isApprovedToken(usdcAddress), true);
        assertEq(vaultGuardians.isApprovedToken(linkAddress), true);
        assertEq(vaultGuardians.isApprovedToken(wethAddress), true);

        assertEq(address(vaultGuardians.getWeth()), wethAddress);
        assertEq(address(vaultGuardians.getTokenOne()), usdcAddress);
        assertEq(address(vaultGuardians.getTokenTwo()), linkAddress);

        assertEq(vaultGuardians.getAavePool(), aavePool);
        assertEq(vaultGuardians.getUniswapV2Router(), uniswapRouter);
    }

    function testBecomeGuardian() public {
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        vm.stopPrank();

        assertEq(address(vaultGuardians.getVaultFromGuardianAndToken(guardian, weth)), wethVault);
    }

    function testBecomeGuardianMovesStakePrice() public {
        weth.mint(mintAmount, guardian);

        vm.startPrank(guardian);
        uint256 wethBalanceBefore = weth.balanceOf(address(guardian));
        weth.approve(address(vaultGuardians), mintAmount);
        vaultGuardians.becomeGuardian(allocationData);
        vm.stopPrank();

        uint256 wethBalanceAfter = weth.balanceOf(address(guardian));
        assertEq(wethBalanceBefore - wethBalanceAfter, vaultGuardians.getGuardianStakePrice());
    }

    function testBecomeGuardianEmitsEvent() public {
        weth.mint(mintAmount, guardian);

        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        vm.expectEmit(false, false, false, true, address(vaultGuardians));
        emit GuardianAdded(guardian, weth);
        vaultGuardians.becomeGuardian(allocationData);
        vm.stopPrank();
    }

    function testCantBecomeTokenGuardianWithoutBeingAWethGuardian() public {
        usdc.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                VaultGuardiansBase.VaultGuardiansBase__NotAGuardian.selector, guardian, address(weth)
            )
        );
        vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        vm.stopPrank();
    }

    modifier hasGuardian() {
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
        _;
    }

    function testUpdatedHoldingAllocationEmitsEvent() public hasGuardian {
        vm.startPrank(guardian);
        vm.expectEmit(false, false, false, true, address(vaultGuardians));
        emit GuardianUpdatedHoldingAllocation(guardian, weth);
        vaultGuardians.updateHoldingAllocation(weth, newAllocationData);
        vm.stopPrank();
    }

    function testOnlyGuardianCanUpdateHoldingAllocation() public hasGuardian {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(VaultGuardiansBase.VaultGuardiansBase__NotAGuardian.selector, user, weth)
        );
        vaultGuardians.updateHoldingAllocation(weth, newAllocationData);
        vm.stopPrank();
    }

    function testQuitGuardian() public hasGuardian {
        vm.startPrank(guardian);
        wethVaultShares.approve(address(vaultGuardians), mintAmount);
        vaultGuardians.quitGuardian();
        vm.stopPrank();

        assertEq(address(vaultGuardians.getVaultFromGuardianAndToken(guardian, weth)), address(0));
    }

    function testQuitGuardianEmitsEvent() public hasGuardian {
        vm.startPrank(guardian);
        wethVaultShares.approve(address(vaultGuardians), mintAmount);
        vm.expectEmit(false, false, false, true, address(vaultGuardians));
        emit GaurdianRemoved(guardian, weth);
        vaultGuardians.quitGuardian();
        vm.stopPrank();
    }

    function testBecomeTokenGuardian() public hasGuardian {
        usdc.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address tokenVault = vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        usdcVaultShares = VaultShares(tokenVault);
        vm.stopPrank();

        assertEq(address(vaultGuardians.getVaultFromGuardianAndToken(guardian, usdc)), tokenVault);
    }

    function testBecomeTokenGuardianOnlyApprovedTokens() public hasGuardian {
        ERC20Mock mockToken = new ERC20Mock();
        mockToken.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        mockToken.approve(address(vaultGuardians), mintAmount);

        vm.expectRevert(
            abi.encodeWithSelector(VaultGuardiansBase.VaultGuardiansBase__NotApprovedToken.selector, address(mockToken))
        );
        vaultGuardians.becomeTokenGuardian(allocationData, mockToken);
        vm.stopPrank();
    }

    function testBecomeTokenGuardianTokenOneName() public hasGuardian {
        usdc.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address tokenVault = vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        usdcVaultShares = VaultShares(tokenVault);
        vm.stopPrank();

        assertEq(usdcVaultShares.name(), vaultGuardians.TOKEN_ONE_VAULT_NAME());
        assertEq(usdcVaultShares.symbol(), vaultGuardians.TOKEN_ONE_VAULT_SYMBOL());
    }

    function testBecomeTokenGuardianTokenTwoNameEmitsEvent() public hasGuardian {
        link.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        link.approve(address(vaultGuardians), mintAmount);

        vm.expectEmit(false, false, false, true, address(vaultGuardians));
        emit GuardianAdded(guardian, link);
        vaultGuardians.becomeTokenGuardian(allocationData, link);
        vm.stopPrank();
    }

    modifier hasTokenGuardian() {
        usdc.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address tokenVault = vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        usdcVaultShares = VaultShares(tokenVault);
        vm.stopPrank();
        _;
    }

    function testCantQuitWethGuardianWithTokens() public hasGuardian hasTokenGuardian {
        vm.startPrank(guardian);
        usdcVaultShares.approve(address(vaultGuardians), mintAmount);
        vm.expectRevert(
            abi.encodeWithSelector(VaultGuardiansBase.VaultGuardiansBase__CantQuitWethWithThisFunction.selector)
        );
        vaultGuardians.quitGuardian(weth);
        vm.stopPrank();
    }

    function testCantQuitWethGuardianWithTokenQuit() public hasGuardian {
        vm.startPrank(guardian);
        wethVaultShares.approve(address(vaultGuardians), mintAmount);
        vm.expectRevert(
            abi.encodeWithSelector(VaultGuardiansBase.VaultGuardiansBase__CantQuitWethWithThisFunction.selector)
        );
        vaultGuardians.quitGuardian(weth);
        vm.stopPrank();
    }

    function testCantQuitWethWithOtherTokens() public hasGuardian hasTokenGuardian {
        vm.startPrank(guardian);
        usdcVaultShares.approve(address(vaultGuardians), mintAmount);
        vm.expectRevert(
            abi.encodeWithSelector(VaultGuardiansBase.VaultGuardiansBase__CantQuitWethWithThisFunction.selector)
        );
        vaultGuardians.quitGuardian();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetVault() public hasGuardian hasTokenGuardian {
        assertEq(address(vaultGuardians.getVaultFromGuardianAndToken(guardian, weth)), address(wethVaultShares));
        assertEq(address(vaultGuardians.getVaultFromGuardianAndToken(guardian, usdc)), address(usdcVaultShares));
    }

    function testIsApprovedToken() public {
        assertEq(vaultGuardians.isApprovedToken(usdcAddress), true);
        assertEq(vaultGuardians.isApprovedToken(linkAddress), true);
        assertEq(vaultGuardians.isApprovedToken(wethAddress), true);
    }

    function testIsNotApprovedToken() public {
        ERC20Mock mock = new ERC20Mock();
        assertEq(vaultGuardians.isApprovedToken(address(mock)), false);
    }

    function testGetAavePool() public {
        assertEq(vaultGuardians.getAavePool(), aavePool);
    }

    function testGetUniswapV2Router() public {
        assertEq(vaultGuardians.getUniswapV2Router(), uniswapRouter);
    }

    function testGetGuardianStakePrice() public {
        assertEq(vaultGuardians.getGuardianStakePrice(), stakePrice);
    }

    function testGetGuardianDaoAndCut() public {
        assertEq(vaultGuardians.getGuardianAndDaoCut(), guardianAndDaoCut);
    }

    //@audit-poc some kind of stealing happening here
    function testBecomeGuardianAndQuitReverts() public {
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        uint256 expectedGuardianInitialShare = stakePrice + stakePrice / guardianAndDaoCut;

        uint256 actualGuardianInitialShare = VaultShares(wethVault).balanceOf(guardian);
        console2.log("expectedGuardianInitialShare: ", expectedGuardianInitialShare); //10.01
        assertEq(expectedGuardianInitialShare, actualGuardianInitialShare);

        vm.stopPrank();
        //user is making a deposit and is depositing 20 ether to the token vault
        weth.mint(20 ether, user);
        vm.startPrank(user);
        weth.approve(address(wethVault), 20 ether);
        VaultShares(wethVault).deposit(20 ether, user);
        uint256 userShare = VaultShares(wethVault).balanceOf(user);
        console2.log("userShare: ", userShare); //53.439999999999999991
        vm.stopPrank();

        //guardian share gets updated
        expectedGuardianInitialShare += userShare / guardianAndDaoCut;
        actualGuardianInitialShare = VaultShares(wethVault).balanceOf(guardian);
        assertEq(expectedGuardianInitialShare, actualGuardianInitialShare, "Shares not same as expected after deposit");

        uint256 wethPresentInVault = weth.balanceOf(wethVault);
        console2.log("wethPresentInVault: ", wethPresentInVault);
        wethVaultShares = VaultShares(wethVault);
        uint256 sharesHeldByGuardian = wethVaultShares.balanceOf(guardian);
        assertGt(sharesHeldByGuardian, stakePrice);

        //now guardian tries to quit being guardian
        uint256 maxRedeemableShares = wethVaultShares.maxRedeem(guardian);
        vm.startPrank(guardian);
        wethVaultShares.approve(address(vaultGuardians), maxRedeemableShares);
        uint256 assetsReturned = vaultGuardians.quitGuardian();
        vm.stopPrank();
        // assertGt(assetsReturned, stakePrice);
        console2.log("assetsReturned: ", assetsReturned);

        //user wants to redeem money
        vm.startPrank(user);
        uint256 userMaxShares = wethVaultShares.maxRedeem(user);
        // wethVaultShares.approve(address(vaultGuardians), userMaxShares);
        uint256 assetsReturnedUser = wethVaultShares.redeem(userMaxShares, user, user);
        vm.stopPrank();

        console2.log("assetsReturnedUser: ", assetsReturnedUser); //9.457755359394703658
    }

    //@audit-poc AddingMoreLiquidityThanAllocated
    function testRevertAddingMoreLiquidityThanAllocated() external hasGuardian hasTokenGuardian {
        usdc.mint(20 ether, user);
        vm.startPrank(user);
        usdc.approve(address(usdcVaultShares), 20 ether);
        VaultShares(usdcVaultShares).deposit(20 ether, user);
        vm.stopPrank();

        vm.prank(guardian);
        vaultGuardians.updateHoldingAllocation(usdc, newAllocationData);
        vm.expectRevert();
        VaultShares(usdcVaultShares).rebalanceFunds();
    }

    //@audit-poc MEV attack with update allocation
    function testMEVAttackWithUpdateAllocationByNode() external hasGuardian hasTokenGuardian {
        // deal(address(usdc), address(usdcVaultShares), 100 ether);
        //user (node) wants to make a deposit
        // meanwhile the updateAllocation function is triggered by guardian
        // Node runs the updateAllocation first then deposit
        //user is making a deposit and is depositing 20 ether to the token vault
        usdc.mint(20 ether, user);
        vm.startPrank(user);
        usdc.approve(address(usdcVaultShares), 20 ether);
        VaultShares(usdcVaultShares).deposit(20 ether, user);
        uint256 userShare = VaultShares(usdcVaultShares).balanceOf(user);
        console2.log("userShare: ", userShare); //10.02
        vm.stopPrank();

        vm.prank(guardian);
        vaultGuardians.updateHoldingAllocation(usdc, newAllocationData);

        VaultShares(usdcVaultShares).rebalanceFunds();

        usdc.mint(20 ether, user);
        vm.startPrank(user);
        usdc.approve(address(usdcVaultShares), 20 ether);
        VaultShares(usdcVaultShares).deposit(20 ether, user);
        uint256 userShareNew = VaultShares(usdcVaultShares).balanceOf(user);
        //Without Rebalancing: 106.986879999999999982
        //WithRebalancing: 1003603199999999999920.079999999999999995
        console2.log("userShare: ", userShareNew);
        vm.stopPrank();

        //user tries to reddem assets
        vm.startPrank(user);
        uint256 userMaxRedeem = VaultShares(usdcVaultShares).maxRedeem(user);
        console2.log("userMaxRedeem: ", userMaxRedeem);

        // uint256 assetsReceived = usdcVaultShares.redeem(userMaxRedeem,user, user);
        // console2.log("assetsReceived: ", assetsReceived);
        // vm.stopPrank();

        deal(address(usdc), address(usdcVaultShares), 1000 ether);

        uint256 assetsReceived = usdcVaultShares.redeem(userMaxRedeem, user, user);
        console2.log("assetsReceived: ", assetsReceived);
        vm.stopPrank();
    }

    //@audit-poc //Similarly the attacker can back run the redeem call after updateHoldingAllocation() goes through
    function testGuardianStealingTheFundsByUpdatingAllocation() external hasGuardian hasTokenGuardian {

        usdc.mint(20 ether, user);
        vm.startPrank(user);
        usdc.approve(address(usdcVaultShares), 20 ether);
        VaultShares(usdcVaultShares).deposit(20 ether, user);
        uint256 userShare = VaultShares(usdcVaultShares).balanceOf(user);
        console2.log("userShare: ", userShare);
        vm.stopPrank();
        

        uint256 guardianShare = VaultShares(usdcVaultShares).balanceOf(guardian);
        console2.log("guardianShare: ", guardianShare);
        
        // vm.prank(user);
        // uint256 assetsRecoveredByUser = VaultShares(usdcVaultShares).redeem(userShare, user, user);
        // console2.log("assetsRecoveredByUser: ", assetsRecoveredByUser);

        AllocationData memory allocationDataNew = AllocationData(1000, 0, 0);
        vm.prank(guardian);
        vaultGuardians.updateHoldingAllocation(usdc, allocationDataNew);
        
        //before calling the quit guardian, guardian waits for enough tokens to accumulate
        deal(address(usdc), address(usdcVaultShares), 1000 ether);

        vm.prank(user);
        uint256 assetsRecoveredByUser = VaultShares(usdcVaultShares).redeem(userShare, user, user);
        console2.log("assetsRecoveredByUser: ", assetsRecoveredByUser);

        vm.startPrank(guardian);
        VaultShares(usdcVaultShares).approve(address(vaultGuardians), guardianShare);
        uint256 assetsRecovered = vaultGuardians.quitGuardian(usdc);
        vm.stopPrank();
    
        console2.log("assetsRecovered: ", assetsRecovered); //200.279951279549527148
    }

    //@audit-poc Guardian can manipulate the allocatio data based off the profits he wants to make before quitting
    function testUpdateAllocationWithGuradianQuittingCanCauseDOSOnWithdrawals() external hasGuardian hasTokenGuardian {
        //guardian has made a deposit by becoming a token guardian
        //user has made the deposit as well
        uint256 userAmountToDeposit = 20 ether;
        usdc.mint(userAmountToDeposit, user);
        vm.startPrank(user);
        usdc.approve(address(usdcVaultShares), userAmountToDeposit);
        VaultShares(usdcVaultShares).deposit(userAmountToDeposit, user);
        uint256 userShare = VaultShares(usdcVaultShares).balanceOf(user);
        console2.log("userShare: ", userShare);
        vm.stopPrank();

        address user2 = makeAddr("user 2");
        uint256 user2AmountToDeposit = 30 ether;
        usdc.mint(user2AmountToDeposit, user2);
        vm.startPrank(user2);
        usdc.approve(address(usdcVaultShares), user2AmountToDeposit);
        VaultShares(usdcVaultShares).deposit(user2AmountToDeposit, user2);
        uint256 user2Share = VaultShares(usdcVaultShares).balanceOf(user2);
        console2.log("user2Share: ", user2Share);
        vm.stopPrank();
        
        // AllocationData memory allocationDataNew = AllocationData(newAllocationData);
        vm.prank(guardian);
        vaultGuardians.updateHoldingAllocation(usdc, newAllocationData);
        // VaultShares(usdcVaultShares).rebalanceFunds();

        
        address user3 = makeAddr("user 3");
        uint256 user3AmountToDeposit = 500 ether;
        usdc.mint(user3AmountToDeposit, user3);
        vm.startPrank(user3);
        usdc.approve(address(usdcVaultShares), user3AmountToDeposit);
        VaultShares(usdcVaultShares).deposit(user3AmountToDeposit, user3);
        uint256 user3Share = VaultShares(usdcVaultShares).balanceOf(user3);
        console2.log("user3Share: ", user3Share);
        vm.stopPrank();
       
        
        vm.startPrank(guardian);
        uint256 guardianShare = VaultShares(usdcVaultShares).maxRedeem(guardian);
        VaultShares(usdcVaultShares).approve(address(vaultGuardians), guardianShare);
        uint256 assetsRecovered = vaultGuardians.quitGuardian(usdc);
        vm.stopPrank();
    
        console2.log("assetsRecovered: ", assetsRecovered);

        vm.startPrank(user2);
        uint256 assetsRecoveredUser2 = VaultShares(usdcVaultShares).redeem(user2Share,user2, user2);
        console2.log("assetsRecoveredUser2: ", assetsRecoveredUser2);
    }

    //@audit-poc
    function testGuardianUpdatingAllocaionForIncreasingShares() external hasGuardian{
        uint256 guardianShare = VaultShares(wethVaultShares).balanceOf(guardian);
        console2.log("guardianShare: ",guardianShare);
        vm.prank(guardian);
        vaultGuardians.updateHoldingAllocation(weth, newAllocationData);
        VaultShares(wethVaultShares).rebalanceFunds();


        weth.mint(20 ether, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), 20 ether);
        VaultShares(wethVaultShares).deposit(20 ether, user);
        vm.stopPrank();
        uint256 userShare = VaultShares(wethVaultShares).balanceOf(guardian);
        console2.log("userShare: ",userShare);
        guardianShare = VaultShares(wethVaultShares).balanceOf(guardian);
        console2.log("guardianShare after updating allocation: ",guardianShare);//200400000000000010.03
    }

    //@audit-poc Reverting due to excess liquidity provision
    function testInvestmentUnableToGoThrough() external hasGuardian {
        vm.prank(guardian);
        vaultGuardians.updateHoldingAllocation(weth, newAllocationData);
        
        vm.expectRevert();
        //Reverting with ERC20InsufficientBalance
        wethVaultShares.rebalanceFunds();
    }
    //@audit-poc showing discrepancy in the event emission of uniswap invest and divest
    function testDiscrepancyInEventEmission() external {
        weth.mint(mintAmount, guardian);
        uint256 amountToDeosit = stakePrice; //WETH amount
        uint256 amountAddedToUniswap = amountToDeosit * allocationData.uniswapAllocation / 1000;
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        vm.expectEmit();
        //event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);
        emit UniswapInvested(amountAddedToUniswap, 0, 0);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
    }

    //@audit-poc
    function testInvestAndDivest() external hasGuardian{
        wethVaultShares.rebalanceFunds();
    }
}
