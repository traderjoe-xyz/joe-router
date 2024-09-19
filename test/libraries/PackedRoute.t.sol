// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/libraries/PackedRoute.sol";

contract PackedRouteTest is Test {
    PackedRouteLib lib;

    function setUp() public {
        lib = new PackedRouteLib();
    }

    function test_Fuzz_Start(uint256 nbTokens, uint256 nbSwaps) public view {
        nbTokens = bound(nbTokens, 0, 255);
        nbSwaps = bound(nbSwaps, 0, 255);

        bytes memory route = abi.encodePacked(
            uint8(nbTokens),
            new bytes(
                PackedRoute.TOKENS_OFFSET - 1 + PackedRoute.ADDRESS_SIZE * nbTokens + PackedRoute.ROUTE_SIZE * nbSwaps
            )
        );

        (uint256 ptr, uint256 nbTokens_, uint256 nbSwaps_) = lib.start(route);

        assertEq(ptr, PackedRoute.TOKENS_OFFSET + PackedRoute.ADDRESS_SIZE * nbTokens, "test_Fuzz_Start::1");
        assertEq(nbTokens_, nbTokens, "test_Fuzz_Start::2");
        assertEq(nbSwaps_, nbSwaps, "test_Fuzz_Start::3");
    }

    function test_Fuzz_Revert_Start(uint256 nbTokens, uint256 length) public {
        nbTokens = bound(nbTokens, 0, 255);
        uint256 minLength = PackedRoute.TOKENS_OFFSET - 1 + PackedRoute.ADDRESS_SIZE * nbTokens;

        uint256 badLength = bound(length, 0, minLength - 1);
        bytes memory route = abi.encodePacked(uint8(nbTokens), new bytes(badLength));

        vm.expectRevert(PackedRoute.PackedRoute__InvalidLength.selector);
        lib.start(route);

        badLength = bound(length, minLength + 1, minLength + 2048);
        badLength = (badLength - minLength) % PackedRoute.ROUTE_SIZE != 0 ? badLength : badLength + 1;

        route = abi.encodePacked(uint8(nbTokens), new bytes(badLength));

        vm.expectRevert(PackedRoute.PackedRoute__InvalidLength.selector);
        lib.start(route);
    }

    function test_Fuzz_IsTransferTax(bool isTransferTax, bytes memory data) public view {
        bytes memory route = abi.encodePacked(uint8(0), isTransferTax, data);

        assertEq(lib.isTransferTax(route), isTransferTax, "test_Fuzz_IsTransferTax::1");
    }

    function test_Fuzz_NextPrevious(address[] memory tokens, bytes26[] memory details) public view {
        if (tokens.length > 32) {
            assembly {
                mstore(tokens, 32)
            }
        }

        if (details.length > 32) {
            assembly {
                mstore(details, 32)
            }
        }

        uint256 length = PackedRoute.ADDRESS_SIZE * tokens.length + PackedRoute.ROUTE_SIZE * details.length;

        bytes memory route = abi.encodePacked(uint8(tokens.length), uint8(0), new bytes(length));

        unchecked {
            uint256 ptr_ = PackedRoute.TOKENS_OFFSET;
            for (uint256 i = 0; i < tokens.length; i++) {
                assembly {
                    mstore(add(add(route, 32), ptr_), shl(96, mload(add(tokens, add(32, mul(i, 32))))))
                }
                ptr_ += PackedRoute.ADDRESS_SIZE;
            }

            for (uint256 i = 0; i < details.length; i++) {
                assembly {
                    mstore(add(add(route, 32), ptr_), mload(add(details, add(32, mul(i, 32)))))
                }
                ptr_ += PackedRoute.ROUTE_SIZE;
            }
        }

        this._nextPrevious(tokens, details, route);
    }

    function _nextPrevious(address[] calldata tokens, bytes26[] calldata details, bytes calldata route) public pure {
        (uint256 ptr, uint256 nbTokens, uint256 nbSwaps) = PackedRoute.start(route);

        assertEq(nbTokens, tokens.length, "test_Fuzz_NextPrevious::1");
        assertEq(nbSwaps, details.length, "test_Fuzz_NextPrevious::2");
        assertEq(ptr, PackedRoute.TOKENS_OFFSET + PackedRoute.ADDRESS_SIZE * nbTokens, "test_Fuzz_NextPrevious::1");

        uint256 startPtr = ptr;

        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(PackedRoute.token(route, i), tokens[i], "test_Fuzz_NextPrevious::3");
        }

        bytes32 value;
        for (uint256 i = 0; i < details.length; i++) {
            (ptr, value) = PackedRoute.next(route, ptr);

            assertEq(ptr, startPtr + PackedRoute.ROUTE_SIZE * (i + 1), "test_Fuzz_NextPrevious::4");
            assertEq(
                value & 0xffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000,
                details[i],
                "test_Fuzz_NextPrevious::5"
            );

            (address pair, uint256 percent, uint256 flags, uint256 tokenInId, uint256 tokenOutId) =
                PackedRoute.decode(value);

            uint256 detail = uint256(bytes32(details[i]));

            assertEq(pair, address(uint160(detail >> 96)), "test_Fuzz_NextPrevious::6");
            assertEq(percent, uint16(detail >> 80), "test_Fuzz_NextPrevious::7");
            assertEq(flags, uint16(detail >> 64), "test_Fuzz_NextPrevious::8");
            assertEq(tokenInId, uint8(detail >> 56), "test_Fuzz_NextPrevious::9");
            assertEq(tokenOutId, uint8(detail >> 48), "test_Fuzz_NextPrevious::10");
        }

        for (uint256 i = details.length; i > 0; i--) {
            (ptr, value) = PackedRoute.previous(route, ptr);

            assertEq(ptr, startPtr + PackedRoute.ROUTE_SIZE * (i - 1), "test_Fuzz_NextPrevious::11");
            assertEq(
                value & 0xffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000,
                details[i - 1],
                "test_Fuzz_NextPrevious::12"
            );

            (address pair, uint256 percent, uint256 flags, uint256 tokenInId, uint256 tokenOutId) =
                PackedRoute.decode(value);

            uint256 detail = uint256(bytes32(details[i - 1]));

            assertEq(pair, address(uint160(detail >> 96)), "test_Fuzz_NextPrevious::13");
            assertEq(percent, uint16(detail >> 80), "test_Fuzz_NextPrevious::14");
            assertEq(flags, uint16(detail >> 64), "test_Fuzz_NextPrevious::15");
            assertEq(tokenInId, uint8(detail >> 56), "test_Fuzz_NextPrevious::16");
            assertEq(tokenOutId, uint8(detail >> 48), "test_Fuzz_NextPrevious::17");
        }
    }
}

contract PackedRouteLib {
    function token(bytes calldata route, uint256 id) external pure returns (address t) {
        return PackedRoute.token(route, id);
    }

    function isTransferTax(bytes calldata route) external pure returns (bool b) {
        return PackedRoute.isTransferTax(route);
    }

    function start(bytes calldata route) external pure returns (uint256 ptr, uint256 nbTokens, uint256 nbSwaps) {
        return PackedRoute.start(route);
    }

    function next(bytes calldata route, uint256 ptr) external pure returns (uint256 nextPtr, bytes32 value) {
        return PackedRoute.next(route, ptr);
    }

    function previous(bytes calldata route, uint256 ptr) external pure returns (uint256 previousPtr, bytes32 value) {
        return PackedRoute.previous(route, ptr);
    }

    function decode(bytes32 value)
        external
        pure
        returns (address pair, uint256 percent, uint256 flags, uint256 tokenInId, uint256 tokenOutId)
    {
        return PackedRoute.decode(value);
    }
}
