### [H-1] Incorrect Liquidity Provision Calculation Leading to Higher Than Expected Deposits in Uniswap inside `UniswapAdapter::_uniswapInvest`

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

### [L-1] Excessive Token Approval Beyond Required Amount iniside `UniswapAdapter::_uniswapInvest`

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
