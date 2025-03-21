// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TokenLib.sol";

/**
 * @title RouterLib
 * @dev Helper library for router operations, such as validateAndTransfer, transfer, and swap.
 * The router must implement a fallback function that uses `validateAndTransfer` to validate the allowance
 * and transfer the tokens and functions that uses `swap` to call the router logic to swap tokens.
 * The router logic must implement the `swapExactIn` and `swapExactOut` functions to swap tokens and
 * use the `transfer` function to transfer tokens from the router according to the route selected.
 */
library RouterLib {
    error RouterLib__ZeroAmount();
    error RouterLib__InsufficientAllowance(uint256 allowance, uint256 amount);

    /**
     * @dev Returns the slot for the allowance of a token for a sender from an address.
     */
    function getAllowanceSlot(
        mapping(bytes32 key => uint256) storage allowances,
        address token,
        address sender,
        address from
    ) internal pure returns (bytes32 s) {
        assembly ("memory-safe") {
            mstore(0, shl(96, token))
            mstore(20, shl(96, sender))

            // Overwrite the last 8 bytes of the free memory pointer with zero,
            //which should always be zeros
            mstore(40, shl(96, from))

            let key := keccak256(0, 60)

            mstore(0, key)
            mstore(32, allowances.slot)

            s := keccak256(0, 64)
        }
    }

    /**
     * @dev Validates the allowance of a token for a sender from an address, and transfers the token.
     *
     * Requirements:
     * - The allowance must be greater than or equal to the amount.
     * - The amount must be greater than zero.
     * - If from is not the router, the token must have been approved for the router.
     */
    function validateAndTransfer(mapping(bytes32 key => uint256) storage allowances) internal {
        address token;
        address from;
        address to;
        uint256 amount;
        uint256 allowance;

        uint256 success;
        assembly ("memory-safe") {
            token := shr(96, calldataload(4))
            from := shr(96, calldataload(24))
            to := shr(96, calldataload(44))
            amount := calldataload(64)
        }

        bytes32 allowanceSlot = getAllowanceSlot(allowances, token, msg.sender, from);

        assembly ("memory-safe") {
            allowance := sload(allowanceSlot)

            if iszero(lt(allowance, amount)) {
                success := 1

                sstore(allowanceSlot, sub(allowance, amount))
            }
        }

        if (amount == 0) revert RouterLib__ZeroAmount(); // Also prevent calldata <= 64
        if (success == 0) revert RouterLib__InsufficientAllowance(allowance, amount);

        from == address(this) ? TokenLib.transfer(token, to, amount) : TokenLib.transferFrom(token, from, to, amount);
    }

    /**
     * @dev Calls the router to transfer tokens from an account to another account.
     *
     * Requirements:
     * - The call must succeed.
     * - The target contract must use `validateAndTransfer` inside its fallback function to validate the allowance
     *   and transfer the tokens accordingly.
     */
    function transfer(address router, address token, address from, address to, uint256 amount) internal {
        assembly ("memory-safe") {
            let m0x40 := mload(0x40)

            mstore(0, shr(32, shl(96, token)))
            mstore(24, shl(96, from))
            mstore(44, shl(96, to))
            mstore(64, amount)

            if iszero(call(gas(), router, 0, 0, 96, 0, 0)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            mstore(0x40, m0x40)
        }
    }

    /**
     * @dev Swaps tokens using the router logic.
     * It will also set the allowance for the logic contract to spend the token from the sender and reset it
     * after the swap is done.
     *
     * Requirements:
     * - The logic contract must not be the zero address.
     * - The call must succeed.
     * - The logic contract must call this contract's fallback function to validate the allowance and transfer the tokens.
     */
    function swap(
        mapping(bytes32 key => uint256) storage allowances,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address from,
        address to,
        bytes calldata route,
        bool exactIn,
        address logic
    ) internal returns (uint256 totalIn, uint256 totalOut) {
        bytes32 allowanceSlot = getAllowanceSlot(allowances, tokenIn, logic, from);

        uint256 length = 256 + route.length; // 32 * 6 + 32 + 32 + route.length
        bytes memory data = new bytes(length);

        assembly ("memory-safe") {
            sstore(allowanceSlot, amountIn)

            switch exactIn
            // swapExactIn(tokenIn, tokenOut, amountIn, amountOut, from, to, route)
            // swapExactOut(tokenIn, tokenOut, amountOut, amountIn, from, to, route)
            case 1 { mstore(data, 0xbd084435) }
            default { mstore(data, 0xcb7e0007) }

            mstore(add(data, 32), tokenIn)
            mstore(add(data, 64), tokenOut)
            mstore(add(data, 96), amountIn)
            mstore(add(data, 128), amountOut)
            mstore(add(data, 160), from)
            mstore(add(data, 192), to)
            mstore(add(data, 224), 224) // 32 * 6 + 32
            mstore(add(data, 256), route.length)
            calldatacopy(add(data, 288), route.offset, route.length)

            if iszero(call(gas(), logic, 0, add(data, 28), add(length, 4), 0, 64)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            totalIn := mload(0)
            totalOut := mload(32)

            sstore(allowanceSlot, 0)
        }
    }
}
