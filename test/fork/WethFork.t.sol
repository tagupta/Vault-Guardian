// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {VaultShares} from "../../src/protocol/VaultShares.sol";

import {Fork_Test} from "./Fork.t.sol";
import {console2} from 'forge-std/console2.sol';
import {IUniswapV2Factory} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import {IUniswapV2Router02} from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import  {UniswapV2Library} from '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import {IUniswapV2Pair} from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

contract WethForkTest is Fork_Test {
    address public guardian = makeAddr("guardian");
    address public user = makeAddr("user");

    VaultShares public wethVaultShares;
    VaultShares public usdcVaultShares;

    uint256 guardianAndDaoCut;
    uint256 stakePrice;
    uint256 mintAmount = 100 ether;

    // 500 hold, 250 uniswap, 250 aave
    AllocationData allocationData = AllocationData(500, 250, 250);
    AllocationData newAllocationData = AllocationData(0, 500, 500);

    function setUp() public virtual override {
        Fork_Test.setUp();
    }

    modifier hasGuardian() {
        //@audit-low there doesn't seem to work for mainnet rather do this
        deal(address(weth), guardian, mintAmount);
        // weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
        _;
    }

    function testDepositAndWithdraw() public {}

    function testPairContractDoesNotExistForWethVault() external {
        address tokenA = address(weth) < address(usdc) ? address(weth) : address(usdc);
        address tokenB = address(weth) < address(usdc)? address(usdc) : address(weth);
        IUniswapV2Factory factoryContract = IUniswapV2Factory((IUniswapV2Router02(uniswapRouter)).factory());
     
        assert(address(factoryContract) == 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

        address pair = UniswapV2Library.pairFor(address(factoryContract), tokenA, tokenB);
        console2.log("Pair: ", pair);
        
        IERC20 uniswapLiquidityToken = IERC20(factoryContract.getPair(tokenA, tokenB));
        console2.log("uniswapLiquidityToken: ", address(uniswapLiquidityToken));

        deal(address(weth), pair, 20 ether);
        deal(address(usdc), pair, 20 ether);
        
       
        deal(address(weth), guardian, mintAmount);
        // weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();

        address lpToken = wethVaultShares.getUniswapLiquidtyToken();
        console2.log("lpToken: ", lpToken);
        // wethVaultShares.rebalanceFunds();
    }

    function testingDivestforUSDCVault() external hasGuardian{
        address tokenA = address(weth) < address(usdc) ? address(weth) : address(usdc);
        address tokenB = address(weth) < address(usdc)? address(usdc) : address(weth);
        IUniswapV2Factory factoryContract = IUniswapV2Factory((IUniswapV2Router02(uniswapRouter)).factory());

        address pair = UniswapV2Library.pairFor(address(factoryContract), tokenA, tokenB);
        console2.log("Pair: ", pair);

        IERC20 uniswapLiquidityToken = IERC20(factoryContract.getPair(tokenA, tokenB));
        console2.log("uniswapLiquidityToken: ", address(uniswapLiquidityToken));

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        console2.log(reserve0, reserve1);
        deal(address(usdc), guardian, mintAmount);
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address usdcVault = vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        usdcVaultShares = VaultShares(usdcVault);
        vm.stopPrank();

        address lpToken = usdcVaultShares.getUniswapLiquidtyToken();
        console2.log("lpToken: ", lpToken);

        uint256 uniswapLPTokensMinted = uniswapLiquidityToken.balanceOf(address(usdcVaultShares));
        uint256 aaveATokenAmount = IERC20(usdcVaultShares.getAaveAToken()).balanceOf(address(usdcVaultShares));
        console2.log(uniswapLPTokensMinted, aaveATokenAmount);


    }
}
