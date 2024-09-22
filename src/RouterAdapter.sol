// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Flags} from "./libraries/Flags.sol";
import {PairInteraction} from "./libraries/PairInteraction.sol";
import {TokenLib} from "./libraries/TokenLib.sol";

abstract contract RouterAdapter {
    error RouterAdapter__InvalidId();
    error RouterAdapter__InsufficientLBLiquidity();
    error RouterAdapter__UniswapV3SwapCallbackOnly(int256 amount0Delta, int256 amount1Delta);

    uint160 internal constant MIN_SWAP_SQRT_RATIO_UV3 = 4295128739 + 1;
    uint160 internal constant MAX_SWAP_SQRT_RATIO_UV3 = 1461446703485210103287273052203988822378723970342 - 1;

    address private immutable _routerV2_0;

    address private _callback = address(0xdead);

    constructor(address routerV2_0) {
        _routerV2_0 = routerV2_0;
    }

    function _getAmountIn(address pair, uint256 flags, uint256 amountOut) internal returns (uint256) {
        uint256 id = Flags.id(flags);

        if (id == Flags.UNISWAP_V2_ID) {
            return _getAmountInUV2(pair, flags, amountOut);
        } else if (id == Flags.TRADERJOE_LEGACY_LB_ID) {
            return _getAmountInLegacyLB(pair, flags, amountOut);
        } else if (id == Flags.TRADERJOE_LB_ID) {
            return _getAmountInLB(pair, flags, amountOut);
        } else if (id == Flags.UNISWAP_V3_ID) {
            return _getAmountInUV3(pair, flags, amountOut);
        } else {
            revert RouterAdapter__InvalidId();
        }
    }

    function _swap(address pair, address tokenIn, uint256 amountIn, address recipient, uint256 flags)
        internal
        returns (uint256 amountOut)
    {
        uint256 id = Flags.id(flags);

        if (id == Flags.UNISWAP_V2_ID) {
            amountOut = _swapUV2(pair, flags, amountIn, recipient);
        } else if (id == Flags.TRADERJOE_LEGACY_LB_ID) {
            amountOut = _swapLegacyLB(pair, flags, recipient);
        } else if (id == Flags.TRADERJOE_LB_ID) {
            amountOut = _swapLB(pair, flags, recipient);
        } else if (id == Flags.UNISWAP_V3_ID) {
            amountOut = _swapUV3(pair, flags, recipient, amountIn, tokenIn);
        } else {
            revert RouterAdapter__InvalidId();
        }
    }

    /* Uniswap V2 */

    function _getAmountInUV2(address pair, uint256 flags, uint256 amountOut) internal view returns (uint256) {
        (uint256 reserveIn, uint256 reserveOut) = PairInteraction.getReservesUV2(pair, Flags.zeroForOne(flags));
        return (reserveIn * amountOut * 1000 - 1) / ((reserveOut - amountOut) * 997) + 1;
    }

    function _swapUV2(address pair, uint256 flags, uint256 amountIn, address recipient)
        internal
        returns (uint256 amountOut)
    {
        bool ordered = Flags.zeroForOne(flags);
        (uint256 reserveIn, uint256 reserveOut) = PairInteraction.getReservesUV2(pair, ordered);

        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);

        (uint256 amount0, uint256 amount1) = ordered ? (uint256(0), amountOut) : (amountOut, uint256(0));
        PairInteraction.swapUV2(pair, amount0, amount1, recipient);
    }

    /* Legacy LB v2.0 */

    function _getAmountInLegacyLB(address pair, uint256 flags, uint256 amountOut)
        internal
        view
        returns (uint256 amountIn)
    {
        return PairInteraction.getSwapInLegacyLB(_routerV2_0, pair, amountOut, Flags.zeroForOne(flags));
    }

    function _swapLegacyLB(address pair, uint256 flags, address recipient) internal returns (uint256 amountOut) {
        return PairInteraction.swapLegacyLB(pair, Flags.zeroForOne(flags), recipient);
    }

    /* LB v2.1 and v2.2 */

    function _getAmountInLB(address pair, uint256 flags, uint256 amountOut) internal view returns (uint256) {
        (uint256 amountIn, uint256 amountLeft) = PairInteraction.getSwapInLB(pair, amountOut, Flags.zeroForOne(flags));
        if (amountLeft != 0) revert RouterAdapter__InsufficientLBLiquidity();
        return amountIn;
    }

    function _swapLB(address pair, uint256 flags, address recipient) internal returns (uint256 amountOut) {
        return PairInteraction.swapLB(pair, Flags.zeroForOne(flags), recipient);
    }

    /* Uniswap V3 */

    function _getAmountInUV3(address pair, uint256 flags, uint256 amountOut) internal returns (uint256 amountIn) {
        return PairInteraction.getSwapInUV3(pair, Flags.zeroForOne(flags), amountOut);
    }

    function _swapUV3(address pair, uint256 flags, address recipient, uint256 amountIn, address tokenIn)
        internal
        returns (uint256 amountOut)
    {
        _callback = pair;

        return PairInteraction.swapUV3(pair, recipient, Flags.zeroForOne(flags), amountIn, tokenIn);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        if (msg.sender != _callback) revert RouterAdapter__UniswapV3SwapCallbackOnly(amount0Delta, amount1Delta);
        _callback = address(0xdead);

        TokenLib.transfer(
            address(uint160(uint256(bytes32(data)))),
            msg.sender,
            uint256(amount0Delta > 0 ? amount0Delta : amount1Delta)
        );
    }
}
