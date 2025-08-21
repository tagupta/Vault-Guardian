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

### [H-2] Missing Token Approval for Uniswap Router Before Swap Operation for `counterPartyToken` inside `UniswapAdapter::_uniswapDivest` leading to Denial of Service (DOS)

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

### [M-1] Incorrect return value from `UniswapAdapter::_uniswapDivest`, excluding initial token amount

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
