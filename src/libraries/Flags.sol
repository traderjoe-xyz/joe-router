// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Flags
 * @dev Helper library for parsing flags received from a packed route
 * The flags are a uint16 variable that contains the following information:
 * - zeroForOne: The first bit of the flags variable (0: false, 1: true)
 * - callback: The second bit of the flags variable (0: false, 1: true)
 * - id: The last 8 bits of the flags variable (1-255)
 * Note that the bits 2-7 are unused for now, and might be used in the future
 */
library Flags {
    uint256 internal constant ONE_FOR_ZERO = 0;
    uint256 internal constant ZERO_FOR_ONE = 1;
    uint256 internal constant CALLBACK = 2;

    uint256 internal constant ID_OFFSET = 8;
    uint256 internal constant ID_MASK = 0xff00;

    uint256 internal constant UNISWAP_V2_ID = 1 << ID_OFFSET;
    uint256 internal constant LFJ_LEGACY_LIQUIDITY_BOOK_ID = 2 << ID_OFFSET;
    uint256 internal constant LFJ_LIQUIDITY_BOOK_ID = 3 << ID_OFFSET; // v2.1 and v2.2 have the same ABI for swaps
    uint256 internal constant UNISWAP_V3_ID = 4 << ID_OFFSET;
    uint256 internal constant LFJ_TOKEN_MILL_ID = 5 << ID_OFFSET;
    uint256 internal constant LFJ_TOKEN_MILL_V2_ID = 6 << ID_OFFSET;

    /**
     * @dev Returns the id of the flags variable
     */
    function id(uint256 flags) internal pure returns (uint256 idx) {
        return flags & ID_MASK;
    }

    /**
     * @dev Returns whether the zeroForOne flag is set
     */
    function zeroForOne(uint256 flags) internal pure returns (bool) {
        return flags & ZERO_FOR_ONE == ZERO_FOR_ONE;
    }

    /**
     * @dev Returns whether the callback flag is set
     */
    function callback(uint256 flags) internal pure returns (bool) {
        return flags & CALLBACK == CALLBACK;
    }
}
