// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IUniswapV2Router01} from "../../vendor/IUniswapV2Router01.sol";
import {IUniswapV2Factory} from "../../vendor/IUniswapV2Factory.sol";
import {AStaticUSDCData, IERC20} from "../../abstract/AStaticUSDCData.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapAdapter is AStaticUSDCData {
    error UniswapAdapter__TransferFailed();

    using SafeERC20 for IERC20;

    IUniswapV2Router01 internal immutable i_uniswapRouter;
    IUniswapV2Factory internal immutable i_uniswapFactory;

    address[] private s_pathArray;

    event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);
    event UniswapDivested(uint256 tokenAmount, uint256 wethAmount);

    constructor(address uniswapRouter, address weth, address tokenOne) AStaticUSDCData(weth, tokenOne) {
        i_uniswapRouter = IUniswapV2Router01(uniswapRouter);
        i_uniswapFactory = IUniswapV2Factory(IUniswapV2Router01(i_uniswapRouter).factory());
    }

    // slither-disable-start reentrancy-eth
    // slither-disable-start reentrancy-benign
    // slither-disable-start reentrancy-events
    /**
     * @notice The vault holds only one type of asset token. However, we need to provide liquidity to Uniswap in a pair
     * @notice So we swap out half of the vault's underlying asset token for WETH if the asset token is USDC or WETH
     * @notice However, if the asset token is WETH, we swap half of it for USDC (tokenOne)
     * @notice The tokens we obtain are then added as liquidity to Uniswap pool, and LP tokens are minted to the vault
     * @param token The vault's underlying asset token
     * @param amount The amount of vault's underlying asset token to use for the investment
     */
    function _uniswapInvest(IERC20 token, uint256 amount) internal {
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;
        // We will do half in WETH and half in the token
        uint256 amountOfTokenToSwap = amount / 2;
        // the path array is supplied to the Uniswap router, which allows us to create swap paths
        // in case a pool does not exist for the input token and the output token
        // however, in this case, we are sure that a swap path exists for all pair permutations of WETH, USDC and LINK
        // (excluding pair permutations including the same token type)
        // the element at index 0 is the address of the input token
        // the element at index 1 is the address of the output token
        s_pathArray = [address(token), address(counterPartyToken)];

        bool succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        //@audit-med missing handling of minimum tokens a user should receive. can lead to slippage
        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: amountOfTokenToSwap,
            amountOutMin: 0,
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });

        succ = counterPartyToken.approve(address(i_uniswapRouter), amounts[1]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }
        //@audit-low causing excess approval than needed, amountOfTokenToSwap should be used only
        succ = token.approve(address(i_uniswapRouter), amountOfTokenToSwap + amounts[0]);
        if (!succ) {
            revert UniswapAdapter__TransferFailed();
        }

        // amounts[1] should be the WETH amount we got back
        //@audit-q why has it defined the liquidty of tokenA as amountOfTokenToSwap + amounts[0], but not just amountOfTokenToSwap
        (uint256 tokenAmount, uint256 counterPartyTokenAmount, uint256 liquidity) = i_uniswapRouter.addLiquidity({
            tokenA: address(token),
            tokenB: address(counterPartyToken),
            //@audit-high Incorrect token amount calculation for liquidity provision
            amountADesired: amountOfTokenToSwap + amounts[0],
            amountBDesired: amounts[1],
            //@audit-med Setting these to 0 provides no MEV/sandwich attack protection
            amountAMin: 0,
            amountBMin: 0,
            to: address(this),
            deadline: block.timestamp
        });
        //@audit-med inconistency with the event emission
        // event UniswapInvested(uint256 tokenAmount, uint256 wethAmount, uint256 liquidity);
        emit UniswapInvested(tokenAmount, counterPartyTokenAmount, liquidity);
    }

    /**
     * @notice The LP tokens of the added liquidity are burnt
     * @notice The other token (which isn't the vault's underlying asset token) is swapped for the vault's underlying asset token
     * @param token The vault's underlying asset token
     * @param liquidityAmount The amount of LP tokens to burn
     */
    //@audit-info no netspec for return parameter
    function _uniswapDivest(IERC20 token, uint256 liquidityAmount) internal returns (uint256 amountOfAssetReturned) {
        IERC20 counterPartyToken = token == i_weth ? i_tokenOne : i_weth;
        
        //@audit-high not approval given for the access of LP tokens
        //@audit-med no protection against slippage
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
        //@audit-med no protection against slippage
        //[counterPartyToken - 0, underlyingToken - 1]
        //@audit-high missing approval for counterParty token
        //counterPartyToken.approve(address(i_uniswapRouter), counterPartyTokenAmount);

        uint256[] memory amounts = i_uniswapRouter.swapExactTokensForTokens({
            amountIn: counterPartyTokenAmount,
            amountOutMin: 0,
            path: s_pathArray,
            to: address(this),
            deadline: block.timestamp
        });
        //tokenAmount, wethAmount
        //@audit-med think there is an issue with the emission. The event expects wethAmount but you're passing amounts[1] which could be any token depending on the swap direction. This is misleading and inconsistent
        //total underlying token amount = tokenAmount + amounts[1]
        emit UniswapDivested(tokenAmount, amounts[1]);
        //@audit-high incorrect return value tokenAmount + amounts[1]?
        amountOfAssetReturned = amounts[1];
    }
    // slither-disable-end reentrancy-benign
    // slither-disable-end reentrancy-events
    // slither-disable-end reentrancy-eth
}
