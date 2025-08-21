// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library DecimalNormalizer {
    function normalizeAmount(uint256 amount18Decimals, uint256 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount18Decimals;
        } else if (decimals < 18) {
            return amount18Decimals / (10 ** (18 - decimals));
        } else {
            return amount18Decimals * (10 ** (decimals - 18));
        }
    }

    function denormalizeAmount(uint256 amountNativeDecimals, uint256 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amountNativeDecimals;
        } else if (decimals < 18) {
            return amountNativeDecimals * (10 ** (18 - decimals));
        } else {
            return amountNativeDecimals / (10 ** (decimals - 18));
        }
    }
}
