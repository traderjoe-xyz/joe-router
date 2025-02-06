// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PairInteraction
 * @dev Library for interacting with Uniswap V2, LFJ, and Uniswap V3 pairs.
 */
library PairInteraction {
    error PairInteraction__InvalidReturnData();

    uint256 internal constant MASK_UINT112 = 0xffffffffffffffffffffffffffff;
    uint256 internal constant MIN_SWAP_SQRT_RATIO_UV3 = 4295128739 + 1;
    uint256 internal constant MAX_SWAP_SQRT_RATIO_UV3 = 1461446703485210103287273052203988822378723970342 - 1;

    /**
     * @dev Returns the ordered reserves of a Uniswap V2 pair.
     * If ordered is true, the reserves are returned as (reserve0, reserve1), otherwise as (reserve1, reserve0).
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must be at least 64 bytes.
     */
    function getReservesUV2(address pair, bool ordered) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        uint256 returnDataSize;
        assembly ("memory-safe") {
            mstore(0, 0x0902f1ac) // getReserves()

            if staticcall(gas(), pair, 28, 4, 0, 64) { returnDataSize := returndatasize() }

            switch ordered
            case 0 {
                reserveIn := and(mload(32), MASK_UINT112)
                reserveOut := and(mload(0), MASK_UINT112)
            }
            default {
                reserveIn := and(mload(0), MASK_UINT112)
                reserveOut := and(mload(32), MASK_UINT112)
            }
        }

        if (returnDataSize < 64) revert PairInteraction__InvalidReturnData();
    }

    /**
     * @dev Returns the amount of tokenIn required to get amountOut from a Uniswap V2 pair.
     * The function doesn't check that the pair has any code, `getReservesUV2` should be called first to ensure that.
     *
     * Requirements:
     * - The call must succeed.
     */
    function swapUV2(address pair, uint256 amount0, uint256 amount1, address recipient) internal {
        assembly ("memory-safe") {
            let ptr := mload(0x40)

            mstore(ptr, 0x022c0d9f) // swap(uint256,uint256,address,bytes)
            mstore(add(ptr, 32), amount0)
            mstore(add(ptr, 64), amount1)
            mstore(add(ptr, 96), recipient)
            mstore(add(ptr, 128), 128)
            mstore(add(ptr, 160), 0)

            mstore(0x40, add(ptr, 160)) // update free memory pointer to 160 because 160:192 is 0

            if iszero(call(gas(), pair, 0, add(ptr, 28), 164, 0, 0)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    /**
     * @dev Returns the amount of tokenIn required to get amountOut from a LFJ Legacy LB pair.
     * It uses the router v2.0 helper function `getSwapIn` to get the amount required.
     *
     * Requirements:
     * - The call must succeed.
     * - The router must have code.
     * - The return data must be at least 32 bytes.
     */
    function getSwapInLegacyLB(address router, address pair, uint256 amountOut, bool swapForY)
        internal
        view
        returns (uint256 amountIn)
    {
        uint256 returnDataSize;
        assembly ("memory-safe") {
            let ptr := mload(0x40)

            mstore(ptr, 0x5bdd4b7c) // getSwapIn(address,uint256,bool)
            mstore(add(ptr, 32), pair)
            mstore(add(ptr, 64), amountOut)
            mstore(add(ptr, 96), swapForY)

            mstore(0x40, add(ptr, 128))

            if iszero(staticcall(gas(), router, add(ptr, 28), 100, 0, 32)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returnDataSize := returndatasize()

            amountIn := mload(0)
        }

        if (returnDataSize < 32) revert PairInteraction__InvalidReturnData();
    }

    /**
     * @dev Swaps tokenIn for tokenOut in a LFJ Legacy LB pair.
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must be at least 64 bytes.
     */
    function swapLegacyLB(address pair, bool swapForY, address recipient) internal returns (uint256 amountOut) {
        uint256 returnDataSize;

        assembly ("memory-safe") {
            let m0x40 := mload(0x40)

            mstore(0, 0x53c059a0) // swap(bool,address)
            mstore(32, swapForY)
            mstore(64, recipient)

            if iszero(call(gas(), pair, 0, 28, 68, 0, 64)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returnDataSize := returndatasize()

            switch swapForY
            case 0 { amountOut := mload(0) }
            default { amountOut := mload(32) }

            mstore(0x40, m0x40)
        }

        if (returnDataSize < 64) revert PairInteraction__InvalidReturnData();
    }

    /**
     * @dev Returns the amount of tokenIn required to get amountOut from a LFJ LB pair (v2.0 and v2.1).
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must be at least 64 bytes.
     */
    function getSwapInLB(address pair, uint256 amountOut, bool swapForY)
        internal
        view
        returns (uint256 amountIn, uint256 amountLeft)
    {
        uint256 returnDataSize;
        assembly ("memory-safe") {
            let m0x40 := mload(0x40)

            mstore(0, 0xabcd7830) // getSwapIn(uint128,bool)
            mstore(32, amountOut)
            mstore(64, swapForY)

            if iszero(staticcall(gas(), pair, 28, 68, 0, 64)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returnDataSize := returndatasize()

            amountIn := mload(0)
            amountLeft := mload(32)

            mstore(0x40, m0x40)
        }

        if (returnDataSize < 64) revert PairInteraction__InvalidReturnData();
    }

    /**
     * @dev Swaps tokenIn for tokenOut in a LFJ LB pair (v2.0 and v2.1).
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must be at least 32 bytes.
     */
    function swapLB(address pair, bool swapForY, address recipient) internal returns (uint256 amountOut) {
        uint256 returnDataSize;

        assembly ("memory-safe") {
            let m0x40 := mload(0x40)

            mstore(0, 0x53c059a0) // swap(bool,address)
            mstore(32, swapForY)
            mstore(64, recipient)

            if iszero(call(gas(), pair, 0, 28, 68, 0, 32)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returnDataSize := returndatasize()

            switch swapForY
            case 0 { amountOut := shr(128, mload(16)) }
            default { amountOut := shr(128, mload(0)) }

            mstore(0x40, m0x40)
        }

        if (returnDataSize < 32) revert PairInteraction__InvalidReturnData();
    }

    /**
     * @dev Returns the amount of tokenIn required to get amountOut from a Uniswap V3 pair.
     * The function actually tries to swap token but revert before having to send any token.
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must match the expected format, which is to revert with a
     *   `RouterAdapter__UniswapV3SwapCallbackOnly(int256 amount0Delta, int256 amount1Delta)` error.
     */
    function getSwapInUV3(address pair, bool zeroForOne, uint256 amountOut) internal returns (uint256 amountIn) {
        (uint256 success, uint256 ptr) = callSwapUV3(pair, address(this), zeroForOne, -int256(amountOut), address(0));

        assembly ("memory-safe") {
            // RouterAdapter__UniswapV3SwapCallbackOnly(int256,int256)
            switch and(eq(shr(224, mload(ptr)), 0xcbdb9bb5), iszero(success))
            case 0 {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            default {
                switch zeroForOne
                case 1 { amountIn := mload(add(ptr, 4)) }
                default { amountIn := mload(add(ptr, 36)) }
            }
        }
    }

    /**
     * @dev Swaps tokenIn for tokenOut in a Uniswap V3 pair.
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must be at least 64 bytes.
     */
    function swapUV3(address pair, address recipient, bool zeroForOne, uint256 amountIn, address tokenIn)
        internal
        returns (uint256 actualAmountOut, uint256 actualAmountIn, uint256 expectedHash)
    {
        (uint256 success, uint256 ptr) = callSwapUV3(pair, recipient, zeroForOne, int256(amountIn), tokenIn);

        uint256 returnDataSize;

        assembly ("memory-safe") {
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returnDataSize := returndatasize()

            mstore(add(ptr, 64), tokenIn)
            expectedHash := keccak256(ptr, 96)

            switch zeroForOne
            case 1 {
                actualAmountIn := mload(ptr)
                actualAmountOut := mload(add(ptr, 32))
            }
            default {
                actualAmountOut := mload(ptr)
                actualAmountIn := mload(add(ptr, 32))
            }

            actualAmountOut := sub(0, actualAmountOut) // Invert the sign
        }

        if (returnDataSize < 64) revert PairInteraction__InvalidReturnData();
    }

    /**
     * @dev Returns the hash of the amount deltas and token address for a Uniswap V3 pair.
     * The hash is used to check that the callback contains the expected data.
     */
    function hashUV3(int256 amount0Delta, int256 amount1Delta, address token) internal pure returns (uint256 hash) {
        assembly {
            let ptr := mload(0x40)

            mstore(0, amount0Delta)
            mstore(32, amount1Delta)
            mstore(64, token)

            hash := keccak256(0, 96)

            mstore(0x40, ptr)
        }
    }

    /**
     * @dev Calls the `swap` function of a Uniswap V3 pair.
     * This function doesn't revert on failure, it returns a success flag instead.
     * It also returns the pointer to the return data.
     *
     * Requirements:
     * - The call must succeed.
     */
    function callSwapUV3(address pair, address recipient, bool zeroForOne, int256 deltaAmount, address tokenIn)
        internal
        returns (uint256 success, uint256 ptr)
    {
        uint256 priceLimit = zeroForOne ? MIN_SWAP_SQRT_RATIO_UV3 : MAX_SWAP_SQRT_RATIO_UV3;

        assembly ("memory-safe") {
            ptr := mload(0x40)

            mstore(ptr, 0x128acb08) // swap(address,bool,int256,uint160,bytes)
            mstore(add(ptr, 32), recipient)
            mstore(add(ptr, 64), zeroForOne)
            mstore(add(ptr, 96), deltaAmount)
            mstore(add(ptr, 128), priceLimit)
            mstore(add(ptr, 160), 160)
            mstore(add(ptr, 192), 32)
            mstore(add(ptr, 224), tokenIn)

            mstore(0x40, add(ptr, 256))

            success := call(gas(), pair, 0, add(ptr, 28), 228, ptr, 68)
        }
    }

    /**
     * @dev Returns the amount of tokenIn required to get amountOut from a LFJ Token Mill pair.
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must be at least 32 bytes.
     */
    function getSwapInTM(address pair, uint256 amountOut, bool swapForY)
        internal
        view
        returns (uint256 amountIn, uint256 actualAmountOut)
    {
        uint256 returnDataSize;
        assembly ("memory-safe") {
            let m0x40 := mload(0x40)

            mstore(0, 0xcd56aadc) // getDeltaAmounts(int256,bool)
            mstore(32, sub(0, amountOut))
            mstore(64, swapForY)

            if iszero(staticcall(gas(), pair, 28, 68, 0, 64)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returnDataSize := returndatasize()

            switch swapForY
            case 0 {
                amountIn := mload(32)
                actualAmountOut := mload(0)
            }
            default {
                amountIn := mload(0)
                actualAmountOut := mload(32)
            }

            amountIn := add(amountIn, 1) // Add 1 wei to account for rounding errors
            actualAmountOut := sub(0, actualAmountOut) // Invert the sign

            mstore(0x40, m0x40)
        }

        if (returnDataSize < 64) revert PairInteraction__InvalidReturnData();
    }

    /**
     * @dev Swaps tokenIn for tokenOut in a LFJ Token Mill pair.
     *
     * Requirements:
     * - The call must succeed.
     * - The pair must have code.
     * - The return data must be at least 64 bytes.
     */
    function swapTM(address pair, address recipient, uint256 amountIn, bool swapForY)
        internal
        returns (uint256 amountOut, uint256 actualAmountIn)
    {
        uint256 returnDataSize;

        assembly ("memory-safe") {
            let ptr := mload(0x40)

            mstore(ptr, 0xdc35ff77) // swap(address,int256,bool,bytes,address)
            mstore(add(ptr, 32), recipient)
            mstore(add(ptr, 64), amountIn)
            mstore(add(ptr, 96), swapForY)
            mstore(add(ptr, 128), 160)
            mstore(add(ptr, 160), 0)
            mstore(add(ptr, 192), 0)

            if iszero(call(gas(), pair, 0, add(ptr, 28), 196, 0, 64)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returnDataSize := returndatasize()

            switch swapForY
            case 0 {
                actualAmountIn := mload(32)
                amountOut := mload(0)
            }
            default {
                actualAmountIn := mload(0)
                amountOut := mload(32)
            }

            amountOut := sub(0, amountOut) // Invert the sign
        }

        if (returnDataSize < 64) revert PairInteraction__InvalidReturnData();
    }
}
