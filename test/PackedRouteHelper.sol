// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PackedRoute} from "../src/libraries/PackedRoute.sol";
import {Flags} from "../src/libraries/Flags.sol";

abstract contract PackedRouteHelper {
    uint16 public ONE_FOR_ZERO = 0;
    uint16 public ZERO_FOR_ONE = uint16(Flags.ZERO_FOR_ONE);
    uint16 public CALLBACK = uint16(Flags.CALLBACK);
    uint16 public TJ1_ID = uint16(Flags.UNISWAP_V2_ID);
    uint16 public LB0_ID = uint16(Flags.LFJ_LEGACY_LIQUIDITY_BOOK_ID);
    uint16 public LB12_ID = uint16(Flags.LFJ_LIQUIDITY_BOOK_ID);
    uint16 public UV3_ID = uint16(Flags.UNISWAP_V3_ID);
    uint16 public TM_ID = uint16(Flags.LFJ_TOKEN_MILL_ID);
    uint16 public TMV2_ID = uint16(Flags.LFJ_TOKEN_MILL_V2_ID);

    mapping(address => uint256) public _tokenToId;

    function test() public pure {} // To avoid this contract to be included in coverage

    function _createRoutes(uint256 nbTokens, uint256 nbSwaps) internal pure returns (bytes memory b, uint256 ptr) {
        if (nbTokens > type(uint8).max) revert("Too many tokens");
        ptr = 1;

        uint256 length =
            PackedRoute.TOKENS_OFFSET + PackedRoute.ADDRESS_SIZE * nbTokens + PackedRoute.ROUTE_SIZE * nbSwaps;

        b = new bytes(length + 32); // Safety margin with the free memory pointer

        assembly ("memory-safe") {
            mstore(b, length)
        }

        assembly ("memory-safe") {
            mstore(add(b, 32), shl(248, nbTokens))
        }
    }

    function _setIsTransferTaxToken(bytes memory b, uint256 ptr, bool isTransferTaxToken)
        internal
        pure
        returns (uint256)
    {
        assembly ("memory-safe") {
            mstore(add(add(b, 32), ptr), shl(248, isTransferTaxToken))
        }
        return ptr + 1;
    }

    function _setToken(bytes memory b, uint256 ptr, address token) internal returns (uint256) {
        uint256 id = (ptr - PackedRoute.TOKENS_OFFSET) / PackedRoute.ADDRESS_SIZE;
        if (id > type(uint8).max) revert("Too many tokens");

        _tokenToId[token] = id + 1;

        assembly ("memory-safe") {
            mstore(add(add(b, 32), ptr), shl(96, token))
        }
        return ptr + PackedRoute.ADDRESS_SIZE;
    }

    function _setRoute(
        bytes memory b,
        uint256 ptr,
        address tokenIn,
        address tokenOut,
        address pair,
        uint16 percent,
        uint16 flags
    ) internal view returns (uint256) {
        uint256 tokenInId = _tokenToId[tokenIn] - 1;
        uint256 tokenOutId = _tokenToId[tokenOut] - 1;

        assembly ("memory-safe") {
            let value :=
                or(shl(96, pair), or(shl(80, percent), or(shl(64, flags), or(shl(56, tokenInId), shl(48, tokenOutId)))))
            mstore(add(add(b, 32), ptr), value)
        }

        ptr += PackedRoute.ROUTE_SIZE;

        if (ptr > b.length) revert("Out of bounds");

        return ptr;
    }
}
