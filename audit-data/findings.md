### [H-1] Missing decimal normalization for assets like USDC causing token amount miscalculation

**Description** The functions performs arithmetic operations and token swaps without accounting for different token decimal places. This causes severe **miscalculations** when dealing with tokens that have different decimal precision `(e.g., WETH has 18 decimals, USDC has 6 decimals)`, leading to protocol integration failures such as `Aave error code 51` (insufficient balance/allowance) when attempting to supply calculated amounts.

**Impact**

- Protocol integration failures preventing core functionality
- Massive over/under-calculation of token amounts leading to transaction reverts
- Contract unusable with multi-decimal token pairs

**Proof of Concepts**

- Trying to supply `2.5e18 USDC` _(which is 2,500,000,000,000,000,000 USDC - way too much!)_, but USDC only has 6 decimals.
- This leads to `Aave error code 51` (insufficient balance/allowance) when trying to supply the calculated amount.
- The `supply` function in the `AaveAdapter` contract is called with an incorrect amount due to missing decimal normalization.

Paste this code in a foked mainnet test [file](../test/fork/WethFork.t.sol) to reproduce the issue

<details>
<summary>Proof of Code (POC)</summary>

```js
function testingDivestforUSDCVaultForkMainnet() external hasGuardian {
        deal(address(usdc), guardian, mintAmount);
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address usdcVault = vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        usdcVaultShares = VaultShares(usdcVault);
        vm.stopPrank();
    }
```

This will lead to the following trace:

```json
0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2::supply(USD Coin: [0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48], 2500000000000000000 [2.5e18], VaultShares: [0x6187F206E5b64D97E5136B5779683a923EaEB1B4], 0)
│ │ │ ├─ [50043] 0xF1Cd4193bbc1aD4a23E833170f49d60f3D35a621::supply(USD Coin: [0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48], 2500000000000000000 [2.5e18], VaultShares: [0x6187F206E5b64D97E5136B5779683a923EaEB1B4], 0) [delegatecall]
│ │ │ │ ├─ [48682] 0x39dF4b1329D41A9AE20e17BeFf39aAbd2f049128::1913f161(00000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000036d6377b42a61f4580e165cd6428b990a56407a260bdd067be194c3e3f00cbac8a000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000022b1c8c1227a00000000000000000000000000006187f206e5b64d97e5136b5779683a923eaeb1b40000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
│ │ │ │ │ ├─ [4968] 0x72E95b8931767C79bA4EeE721354d6E99a61D004::scaledTotalSupply() [staticcall]
│ │ │ │ │ │ ├─ [2419] 0xaC725CB59D16C81061BDeA61041a8A5e73DA9EC6::scaledTotalSupply() [delegatecall]
│ │ │ │ │ │ │ └─ ← [Return] 0x0000000000000000000000000000000000000000000000000001046445ceab30
│ │ │ │ │ │ └─ ← [Return] 0x0000000000000000000000000000000000000000000000000001046445ceab30
│ │ │ │ │ ├─ [7482] 0xB0fe3D292f4bd50De902Ba5bDF120Ad66E9d7a39::getSupplyData() [staticcall]
│ │ │ │ │ │ ├─ [4921] 0x15C5620dfFaC7c7366EED66C20Ad222DDbB1eD57::getSupplyData() [delegatecall]
│ │ │ │ │ │ │ └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
│ │ │ │ │ │ └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
│ │ │ │ │ ├─ [4924] 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c::scaledTotalSupply() [staticcall]
│ │ │ │ │ │ ├─ [2375] 0x7EfFD7b47Bfd17e52fB7559d3f924201b9DbfF3d::scaledTotalSupply() [delegatecall]
│ │ │ │ │ │ │ └─ ← [Return] 0x000000000000000000000000000000000000000000000000000124682f786ede
│ │ │ │ │ │ └─ ← [Return] 0x000000000000000000000000000000000000000000000000000124682f786ede
│ │ │ │ │ └─ ← [Revert] 51
│ │ │ │ └─ ← [Revert] 51
│ │ │ └─ ← [Revert] 51
│ │ └─ ← [Revert] 51

```

</details>

**Recommended mitigation**

1. Implement decimal normalization utility. The full code for normalization library is available [here](../src/protocol/DecimalNormalizer.sol)

```js
function normalizeAmount(uint256 amount18Decimals, uint256 decimals) internal pure returns (uint256) {
    if (decimals == 18) {
        return amount18Decimals;
    } else if (decimals < 18) {
        return amount18Decimals / (10 ** (18 - decimals));
    } else {
        return amount18Decimals * (10 ** (decimals - 18));
    }
}
```

2. Update the `UniswapAdapter::_uniswapInvest` and `UniswapAdapter::_uniswapDivest` functions to use the normalization utility when calculating amounts for token swaps and liquidity provision.

3. Similary update the `AaveAdapter::_supply` and `AaveAdapter::_withdraw` functions to use the normalization utility when calculating amounts for Aave supply and withdrawal operations.

### [H-2] `VaultShares::constructor` sets LP Token address to zero for WETH asset causing permanent loss of funds inside uniswap pool

**Description** When the `constructor's` asset parameter is `WETH`, the `getPair()` call becomes `getPair(address(i_weth), address(i_weth))`, attempting to create a pair with the same token twice. Uniswap V2 factory returns `address(0)` for identical token pairs, causing `i_uniswapLiquidityToken` to be set to the **zero address**.

```js
i_uniswapLiquidityToken = IERC20(
  i_uniswapFactory.getPair(address(constructorData.asset), address(i_weth))
);
```

**Impact** Divesting logic depends on LP token balance checks `(liquidityAmount > 0)`, users can never withdraw their funds when the asset is WETH.

```js
    uint256 uniswapLiquidityTokensBalance = i_uniswapLiquidityToken.balanceOf(address(this));
    if (uniswapLiquidityTokensBalance > 0) {
        _uniswapDivest(IERC20(asset()), uniswapLiquidityTokensBalance);
    }
```

**Proof of Concepts**

1. Deploy the `VaultShares` contract with `WETH` as the asset via the `becomeGuardian` function.
2. The `constructor` sets `i_uniswapLiquidityToken` to the zero address.

```js
function testReturnsZeroLPTokenAddressForWETH() external {
        address tokenA = address(weth) < address(usdc) ? address(weth) : address(usdc);
        address tokenB = address(weth) < address(usdc)? address(usdc) : address(weth);
        IUniswapV2Factory factoryContract = IUniswapV2Factory((IUniswapV2Router02(uniswapRouter)).factory());

        address pair = UniswapV2Library.pairFor(address(factoryContract), tokenA, tokenB);
        console2.log("Pair: ", pair);

        IERC20 uniswapLiquidityToken = IERC20(factoryContract.getPair(tokenA, tokenB));
        console2.log("uniswapLiquidityToken: ", address(uniswapLiquidityToken));


        deal(address(weth), guardian, mintAmount);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();

        address lpToken = wethVaultShares.getUniswapLiquidtyToken();
        assertEq(lpToken, address(0));
        console2.log("lpToken: ", lpToken);
    }
```

Log output:

```js
Pair: 0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc;
uniswapLiquidityToken: 0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc;
lpToken: 0x0000000000000000000000000000000000000000;
```

**Recommended mitigation**

```diff
-   i_uniswapLiquidityToken = IERC20(i_uniswapFactory.getPair(address(constructorData.asset), address(i_weth)));
+   address counterToken =
+        address(constructorData.asset) == address(i_weth) ? constructorData.usdc : address(i_weth);
+        i_uniswapLiquidityToken = IERC20(i_uniswapFactory.getPair(address(constructorData.asset), counterToken));
```

### [H-3] `UniswapAdapter::_uniswapInvest` incorrectly calculates liquidity to add, leading to higher than intended deposits in Uniswap

**Description** The `amountADesired` parameter uses `amountOfTokenToSwap + amounts[0]` instead of just `amountOfTokenToSwap`. Since `amounts[0]` equals the input amount to the swap, this doubles the intended liquidity provision amount, potentially depleting more tokens than the guardian intended to invest in uniswap.

**Impact**

- User funds at risk - investing more than intended
- Potential contract insolvency if insufficient balance

**Proof of Concepts**

1. Guardian becomes the guardian of weth vault.
2. Guardian calls `updateHoldingAllocation` to set a new allocation for WETH.
3. Setting the hold allocation to 0, 50% for Uniswap and the remaining 50% for the Aave.
4. Guardian calls `rebalanceFunds` to divest the funds and invest based on the new allocation.
5. The `UniswapAdapter::_uniswapInvest` function is called, which calculates the liquidity provision amount as `amountADesired = amountOfTokenToSwap + amounts[0]`, leading to a higher deposit than intended.
6. The amount allocated to Aave is higher than the available balance, causing the transaction to revert with `ERC20InsufficientBalance`.

```js
function testInvestmentUnableToGoThrough() external hasGuardian {
        vm.prank(guardian);
        vaultGuardians.updateHoldingAllocation(weth, newAllocationData);

        vm.expectRevert();
        //Reverting with ERC20InsufficientBalance
        wethVaultShares.rebalanceFunds();
    }
```

**Recommended mitigation**

```diff
    (uint256 tokenAmount, uint256 counterPartyTokenAmount, uint256 liquidity) = i_uniswapRouter.addLiquidity({
        tokenA: address(token),
        tokenB: address(counterPartyToken),
-       amountADesired: amountOfTokenToSwap + amounts[0],
+       amountADesired: amountOfTokenToSwap,
        amountBDesired: amounts[1],
        // ... rest of parameters
    });
```

### [H-4] `UniswapAdapter::_uniswapDivest` lacks the token approval for Uniswap router before swap operation for `counterPartyToken`, leading to Denial of Service (DOS)

**Description** The function attempts to swap `counterPartyToken` tokens via `swapExactTokensForTokens` without first approving the Uniswap router to spend the tokens.

```js
function _uniswapDivest(IERC20 token, uint256 liquidityAmount) internal returns (uint256 amountOfAssetReturned) {
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;

        (uint256 tokenAmount, uint256 counterPartyTokenAmount) = i_uniswapRouter.removeLiquidity({
            tokenA: address(token),
            tokenB: address(counterPartyToken),
            liquidity: liquidityAmount,
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
        s_pathArray = [address(counterPartyToken), address(token)];

@>      uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: counterPartyTokenAmount,
            amountOutMin: 0,
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });
        emit UniswapDivested(tokenAmount, amounts[1]);
        amountOfAssetReturned = amounts[1];
    }
```

**Impact**

- Function will always revert during swap operation, making divest functionality completely broken
- Users unable to withdraw their invested funds can cause denial of service (DOS) for the vault

**Proof of Concepts**

```js
// After removeLiquidity, contract receives counterPartyToken
(uint256 tokenAmount, uint256 counterPartyTokenAmount) = i_uniswapRouter.removeLiquidity(...);

// This call will REVERT - router has no permission to spend counterPartyToken
uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
    amountIn: counterPartyTokenAmount, // Router tries to spend tokens it can't access
    // ... other parameters
});
// Result: Transaction reverts with "ERC20: transfer amount exceeds allowance"
```

**Recommended mitigation** Add token approval for the Uniswap router before the swap operation

```diff
+   bool succ = counterPartyToken.approve(address(i_uniswapRouter), counterPartyTokenAmount);
+   if (!succ) {
+       revert UniswapAdapter__TransferFailed();
+   }

uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
    amountIn: counterPartyTokenAmount,
    amountOutMin: 0,
    path: s_pathArray,
    to: address(this),
    deadline: block.timestamp
});
```

### [H-5] `VaultShares::deposit` causes incorrect share distribution by not accounting for invested assets

**Description** The `previewDeposit(assets)` function relies on `totalAssets()` to calculate the _share-to-asset_ ratio. However, `ERC4626::totalAssets()` only checks the vault's underlying asset balance and does not account for assets that have already been invested in external protocols.

This results in artificially low `totalAssets()` values, leading to incorrect share calculations where users receive more shares than they should based on the true total vault value.

**Impact**

- Users receive significantly more shares than deserved when assets are invested
- Severe dilution of existing shareholders when vault has low cash reserves

**Proof of Concepts**

- A user deposits assets into the vault, and the function calculates shares based on the current `totalAssets()`.
- Guardian then updates the holding allocation, which invests 50% of the assets into Uniswap and the remaining 50% into Aave.
- When the user deposits again after rebalancing, the function calculates shares based on the new `totalAssets()` which is `0` in this scenario as the vault has no cash reserve.
- Causing highly inflated share amounts to be minted for the user.

Paste this code in test [file](../test/unit/concrete/VaultGuardiansBaseTest.t.sol) to reproduce this issue

<details>
<summary>Proof Of Code (POC)</summary>

```diff
+   // Resolve this issue first by adding correct amount of liquidity to the uniswap pool to simulate this scenario
-   amountADesired: amountOfTokenToSwap + amounts[0],
+   amountADesired: amountOfTokenToSwap,
```

```js
 function testUnfairShareDistributionToUsers() external hasGuardian{
        weth.mint(20 ether, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), 20 ether);
        VaultShares(wethVaultShares).deposit(20 ether, user);
        uint256 userShare = VaultShares(wethVaultShares).balanceOf(user);
        console2.log("userShare: ", userShare); //40.079999999999999995
        vm.stopPrank();

        vm.prank(guardian);
        // Holding 0 amount of assets in the vault
        // Investing 50% of the total assets in uniswap
        // Investing remaining 50% to the Aave
        // newAllocationData = AllocationData(0, 500, 500);
        vaultGuardians.updateHoldingAllocation(weth, newAllocationData);
        // Rebalancing invest assets based off new allocation data
        VaultShares(wethVaultShares).rebalanceFunds();

        assertEq(wethVaultShares.totalAssets(), 0);
        //user deposits again
        weth.mint(20 ether, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), 20 ether);
        VaultShares(wethVaultShares).deposit(20 ether, user);
        uint256 userShareNew = VaultShares(wethVaultShares).balanceOf(user);
        //Without Rebalancing: 106.986879999999999982
        //WithRebalancing: 1003603199999999999920.079999999999999995
        console2.log("userShare: ", userShareNew);
        vm.stopPrank();

        uint256 totalSharesMinted = wethVaultShares.totalSupply();
        vm.expectRevert(Math.MathOverflowedMulDiv.selector);
        wethVaultShares.previewWithdraw(totalSharesMinted);
    }
```

</details>

**Recommended mitigation** Override `totalAssets()` to account for invested amounts

```diff
+   function totalAssets() public view override returns (uint256) {
+       return asset().balanceOf(address(this)) + _getInvestedAssets();
+   }

+   function _getInvestedAssets() internal view returns (uint256) {
+       // Sum all invested positions across protocols
+       uint256 aaveBalance = _getAaveBalance();
+       uint256 uniswapBalance = _getUniswapBalance();
+       return aaveBalance + uniswapBalance;
+   }
```

### [H-6] `VaultShares::deposit` creates undercollaterization due to unbacked share minting for DAO and guardian

**Description** The function **mints** additional fee shares to _guardian_ and _DAO_ addresses `(shares / i_guardianAndDaoCut)` each after already calculating and minting the correct share amount to the user. This creates more total shares than the deposited assets can back, leading to vault **undercollateralization** where total shares exceed the asset backing ratio.

**Impact**

- Vault becomes undercollateralized with unbacked shares
- Dilution of all existing shareholders' value
- Economic loss for all vault participants

**Proof of Concepts**
In the following code, we simulate a scenario where a user deposits assets into the vault, and the function mints additional shares to the guardian and DAO.

Here, the total shares minted exceed the assets backing them, causing the vault to become undercollateralized.

<details>
<summary>Proof Of Code (POC)</summary>

```js
 function testUnbackedSharesMintingCausingUnderCollateralization() external{
        AllocationData memory allocationDataNew = AllocationData(1000, 0, 0);

        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationDataNew);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();

        // user makes a deposit
        weth.mint(7 ether, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), 7 ether);
        wethVaultShares.deposit(7 ether, user);
        vm.stopPrank();

        //user makes another deposit
        weth.mint(5 ether, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), 5 ether);
        wethVaultShares.deposit(5 ether, user);
        vm.stopPrank();

        uint256 totalSharesMinted = wethVaultShares.totalSupply(); //10.02
        console2.log(totalSharesMinted);

        //preview Withdraw
        uint256 actualAssets = wethVaultShares.totalAssets();
        uint256 expectedAssets = wethVaultShares.previewWithdraw(totalSharesMinted);
        console2.log(expectedAssets, actualAssets);
        assertGt(expectedAssets, actualAssets);
    }
```

</details>

**Recommended mitigation**

```diff
 function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        isActive
        nonReentrant
        returns (uint256)
    {
        if (assets > maxDeposit(receiver)) {
            revert VaultShares__DepositMoreThanMax(assets, maxDeposit(receiver));
        }
        uint256 shares = previewDeposit(assets);
-       _deposit(_msgSender(), receiver, assets, shares);
-       _mint(i_guardian, shares / i_guardianAndDaoCut);
-       _mint(i_vaultGuardians, shares / i_guardianAndDaoCut);

+       uint256 grossShares = previewDeposit(assets);
+       uint256 feeShares = grossShares * 2 / i_guardianAndDaoCut; // 2 because guardian + DAO
+       uint256 netSharesForUser = grossShares - feeShares;

+       _deposit(_msgSender(), receiver, assets, netSharesForUser);
+       _mint(i_guardian, feeShares / 2);
+       _mint(i_vaultGuardians, feeShares / 2);
        _investFunds(assets);
        return shares;
    }
```

### [H-7] `VaultShares::deposit` does not reduce the assets amount to invest after fees are deducted for DAO and guardian and returns the incorrect amount of user shares

**Description** The function invests the full deposited assets amount via `_investFunds(assets)` without accounting for the fact that additional fee shares were minted. Since more shares now exist than the original calculation anticipated, the investment amount should be proportionally reduced to maintain proper _asset-to-share_ backing ratio.

The function also returns the incorrect amount of user shares without considering the fee shares that were minted for the guardian and DAO.

```js
function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        isActive
        nonReentrant
        returns (uint256)
    {
        if (assets > maxDeposit(receiver)) {
            revert VaultShares__DepositMoreThanMax(assets, maxDeposit(receiver));
        }
        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
        _mint(i_guardian, shares / i_guardianAndDaoCut);
        _mint(i_vaultGuardians, shares / i_guardianAndDaoCut);
@>      _investFunds(assets);
        return shares;
    }
```

**Impact**

- Over-investment of funds relative to share distribution
- Mismatch between invested assets and total share claims

**Proof of Concepts**

1. A user deposits assets into the vault. and instead of investing the full amount, the function should reduce the assets to invest by the fees.
2. This shows the `actualAmountToInvest` is less than the assets amount that is being invested.

Paste this code in a test [file](../test/unit/concrete/VaultGuardiansBaseTest.t.sol) to reproduce the issue

<details>
<summary>Proof Of Code (POC)</summary>

```js
function testOverInvestmentOfFunds() external{
        AllocationData memory allocationDataNew = AllocationData(1000, 0, 0);

        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationDataNew);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();

        uint256 assetsToInvest = 25 ether;
        weth.mint(assetsToInvest, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), assetsToInvest);

        uint256 userShares = wethVaultShares.previewDeposit(assetsToInvest);
        uint256 feeShares = userShares * 2 / wethVaultShares.getGuardianAndDaoCut();

        uint256 totalSharesCreated = userShares + feeShares;

        // The function invests the full assets amount without reducing it for fees
        // This leads to over-investment of funds relative to the shares created
        uint256 actualAssetsToInvest = assetsToInvest * userShares / totalSharesCreated;
        wethVaultShares.deposit(assetsToInvest, user);
        vm.stopPrank();
        assertLt(actualAssetsToInvest, assetsToInvest);
    }
```

</details>

**Recommended mitigation**

```diff
function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        isActive
        nonReentrant
        returns (uint256)
    {
        if (assets > maxDeposit(receiver)) {
            revert VaultShares__DepositMoreThanMax(assets, maxDeposit(receiver));
        }
        uint256 shares = previewDeposit(assets);
+       uint256 feeShares = (shares / i_guardianAndDaoCut) * 2;
+       uint256 totalSharesCreated = shares + feeShares;
+       uint256 userShares = shares - feeShares;
-       _deposit(_msgSender(), receiver, assets, shares);
+       _deposit(_msgSender(), receiver, assets, userShares);

        _mint(i_guardian, shares / i_guardianAndDaoCut);
        _mint(i_vaultGuardians, shares / i_guardianAndDaoCut);
+       // Calculate the actual amount to invest after accounting for fees
+       uint256 actualAmountToInvest = assets * shares / totalSharesCreated;
-       _investFunds(assets);
+       _investFunds(actualAmountToInvest);
-        return shares;
+        return userShares;
    }
```

### [M-1] `UniswapAdapter::_uniswapDivest` returns incorrect asset amount extracted from Uniswap

**Description** The function returns only `amounts[1]` (tokens received from swap) but ignores `tokenAmount` (tokens received directly from liquidity removal). This results in an incomplete accounting of the total assets returned to the user, potentially causing economic loss in calling contracts that rely on this return value.

Though the return value is not used in the current implementation, it can lead to issues if the function is called by other contracts that expect the total amount returned.

```js
 function _uniswapDivest(IERC20 token, uint256 liquidityAmount) internal returns (uint256 amountOfAssetReturned) {
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;
        (uint256 tokenAmount, uint256 counterPartyTokenAmount) = i_uniswapRouter.removeLiquidity({
            tokenA: address(token),
            tokenB: address(counterPartyToken),
            liquidity: liquidityAmount,
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
        s_pathArray = [address(counterPartyToken), address(token)];
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: counterPartyTokenAmount,
            amountOutMin: 0,
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });
        emit UniswapDivested(tokenAmount, amounts[1]);
@>      amountOfAssetReturned = amounts[1];
    }
```

**Impact**

- Incorrect asset accounting leading to potential economic loss
- Calling contracts may miscalculate available assets

**Proof of Concepts**
Assuming a scenario where a user divests liquidity from Uniswap, the function `_uniswapDivest` is called, and the user expects to receive back the total assets (both direct token receipt and swap proceeds).

```js
// User divests liquidity worth 1000 tokens total
// removeLiquidity returns:
// - tokenAmount = 500 USDC
// - counterPartyTokenAmount = 500 WETH equivalent

// After swap of 500 WETH:
// - amounts[1] = ~500 USDC (from swap)

// INCORRECT: Only returning swap proceeds
amountOfAssetReturned = amounts[1]; // ~500 tokens

// CORRECT: Should return total assets
// amountOfAssetReturned = tokenAmount + amounts[1]; // ~1000 tokens

// Result: User loses credit for 500 tokens
```

**Recommended mitigation**

```diff
-   amountOfAssetReturned = amounts[1];
+   amountOfAssetReturned = tokenAmount + amounts[1];
```

### [L-1] `UniswapAdapter::_uniswapInvest` allows excessive token approval beyond required amount

**Description** The function `_uniswapInvest` approves `amountOfTokenToSwap + amounts[0]` tokens for the Uniswap router during liquidity addition, but `amounts[0]` represents the input amount from the swap (which equals `amountOfTokenToSwap`). This results in approving double the required amount `(2 * amountOfTokenToSwap)`.

```js
  function _uniswapInvest(IERC20 token, uint256 amount) internal {
        .
        .
        .
@>      succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap + amounts[0]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        .
    }
```

**Impact**

1. Unnecessary token approval exposure to the router contract enable a contract to spend more tokens than needed.
2. Gas waste from redundant approval
3. Increased risk of potential token loss if the router contract is compromised or misused.

**Recommended mitigation** Approve only what's needed for liquidity provision

```diff
-   succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap + amounts[0]);
+   succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap);
```

### [L-2] Event Emission Inconsistency in `UniswapAdapter::_uniswapInvest`

**Description** The emitted `UniswapInvested` event uses `counterPartyTokenAmount` as the second parameter, but the event definition says it should specifically be `wethAmount`. This creates inconsistency between definition and implementation, potentially confusing external monitoring systems.

```js
    event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);
    emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);
```

The `counterPartyToken` can be any token WETH or USDC depending on the token being invested, so the event should be updated to reflect this.

**Impact**

- Monitoring and analytics systems may misinterpret event data
- Increases risk of incorrect assumptions about the event data.
- Reduces maintainability of the codebase.

**Proof of Concepts**

Showing the discrepancy in the event emission of `UniswapInvested` via the `becomeGuardian` function call:

```js
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
```

**Recommended mitigation**

1. Update event definition to match implementation

```diff
-   event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);
+   event UniswapInvested(uint256 tokenAmount, uint256 counterPartyTokenAmount, uint256 liquidity);
```

2. Or update emission to match documentation (if WETH is always expected as second parameter):

```diff
-   emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);

+   if (token == i_weth) {
+       emit UniswapInvested(counterPartyTokenAmount, tokenAmount, liquidity);
+   } else {
+       emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);
+   }
```

### [L-3] Event Emission Inconsistency in `UniswapAdapter::_uniswapDivest`

**Description** The emitted `UniswapDivested` event uses `amounts[1]` as the second parameter, but the event definition says it should specifically be `wethAmount`. This creates inconsistency between definition and implementation, potentially confusing external monitoring systems.

```js
    event UniswapDivested(uint256 tokenAmount, uint256 wethAmount);
    emit UniswapDivested(tokenAmount, amounts[1]);
```

**Impact**

- External systems expecting WETH amounts will receive incorrect data
- Event monitoring and analytics systems may misinterpret token flows

**Proof of Concepts**

1. Token = USDC, counterPartyToken = WETH,
2. WETH are swapped for USDC, amounts[1] is NOT WETH rather USDC
3. This leads to confusion as the event suggests WETH amounts, but it is actually USDC amounts.

**Recommended mitigation**

1. Update event definition to match implementation

```diff
-   event UniswapDivested(uint256 tokenAmount, uint256 wethAmount);
+   event UniswapDivested(uint256 tokenAmount, uint256 counterPartyTokenAmount);
```

2. Emit consistent WETH amounts

```diff
-   emit UniswapDivested(tokenAmount, amounts[1]);
+   if (token == i_weth) {
+       emit UniswapDivested(counterPartyTokenAmount, tokenAmount);
+   } else {
+       emit UniswapDivested(tokenAmount, counterPartyTokenAmount);
+   }
```

### [I-1] Empty Interface Definition for `IInvestableUniverseAdapter` with unused import

**Description** The `IInvestableUniverseAdapter` interface is essentially empty and does not define any methods or properties. This can lead to confusion and does not provide any functionality.

This creates dead code that unnecessarily increases the contract's bytecode size and deployment costs while providing no functional value.

**Impact**

- Creates confusion for developers regarding its intended purpose.
- Increases complexity in the codebase without contributing any functionality.
- Adds unnecessary bytecode and deployment overhead.

**Recommended mitigation**

- Remove the empty interface if it is not required.
- If it is intended to serve as a contract abstraction, define meaningful methods and properties that align with its purpose.
- Eliminate unused imports to maintain a clean and maintainable codebase.

### [I-2] Empty Interface Definition for `IVaultGuardians`

**Description** The `IVaultGuardians` interface is declared but does not define any methods or properties.

**Impact**

- May confuse developers about its intended role.
- Adds unnecessary complexity to the codebase without any functionality.
- Slightly increases bytecode and deployment overhead.

**Recommended mitigation**

- Remove the empty interface if it has no functional use.
- If it is intended as a placeholder for future contract abstractions, define the relevant methods and properties that reflect its purpose.

### [I-3] Missing NatSpec Documentation for Interface `IVaultShares`

**Description** The interface `IVaultShares` is defined without NatSpec (/// or /\*_ ... _/) documentation for its purpose or intended usage

**Impact**

- Lowers maintainability and readability of the codebase.
- Increases the risk of incorrect assumptions or misuse by developers.
- Reduces clarity for auditors and integrators relying on the interface.

**Recommended mitigation** Add NatSpec documentation for all interfaces
