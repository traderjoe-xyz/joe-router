// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/libraries/PairInteraction.sol";
import "../../src/RouterAdapter.sol";
import "../interfaces/IUV2Pair.sol";
import "../interfaces/IUV3Pair.sol";
import "../interfaces/ILegacyLBPair.sol";
import "../interfaces/ILegacyLBRouter.sol";
import "../interfaces/ILBPair.sol";
import "../interfaces/ITMPair.sol";

contract PairInteractionTest is Test {
    error CustomError();

    uint256 _case;

    bytes _data;
    bytes _msgData;

    fallback() external {
        uint256 c = _case;

        if (c == 0) {
            _msgData = msg.data;
            c = 1;
        }

        if (c == 1) {
            bytes memory data = _data;

            assembly ("memory-safe") {
                return(add(data, 0x20), mload(data))
            }
        }

        if (c == 2) {
            bytes memory data = _data;

            assembly ("memory-safe") {
                revert(add(data, 0x20), mload(data))
            }
        }
    }

    function test_Fuzz_GetOrderedReservesUV2(bool zeroForOne, uint112 reserve0, uint112 reserve1) public {
        _case = 1;
        _data = abi.encode(reserve0, reserve1);

        (uint256 reserveIn, uint256 reserveOut) = this.getReservesUV2(address(this), zeroForOne);

        (uint256 expectedReserveIn, uint256 expectedReserveOut) =
            zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);

        assertEq(reserveIn, expectedReserveIn, "test_Fuzz_GetOrderedReservesUV2::1");
        assertEq(reserveOut, expectedReserveOut, "test_Fuzz_GetOrderedReservesUV2::2");
    }

    function test_Fuzz_Revert_GetOrderedReservesUV2(bool zeroForOne) public {
        _case = 2;
        _data = new bytes(64);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.getReservesUV2(address(this), zeroForOne);

        _data = new bytes(63);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.getReservesUV2(address(this), zeroForOne);

        _case = 1;

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.getReservesUV2(address(this), zeroForOne);
    }

    function test_Fuzz_SwapUV2(uint256 amount0, uint256 amount1, address recipient) public {
        _case = 0;

        this.swapUV2(address(this), amount0, amount1, recipient);

        assertEq(
            _msgData,
            abi.encodeWithSelector(IUV2Pair.swap.selector, amount0, amount1, recipient, new bytes(0)),
            "test_Fuzz_SwapUV2::1"
        );
    }

    function test_Fuzz_Revert_SwapUV2(uint256 amount0, uint256 amount1, address recipient) public {
        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.swapUV2(address(this), amount0, amount1, recipient);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.swapUV2(address(this), amount0, amount1, recipient);
    }

    function test_Fuzz_GetSwapInLegacyLB(address pair, uint256 amountOut, bool swapForY, uint256 amountIn) public {
        _case = 1;
        _data = abi.encode(amountIn);

        uint256 amount = this.getSwapInLegacyLB(address(this), pair, amountOut, swapForY);

        assertEq(amount, amountIn, "test_Fuzz_GetSwapInLegacyLB::1");
    }

    function test_Fuzz_Revert_GetSwapInLegacyLB(address pair, uint256 amountOut, bool swapForY) public {
        _case = 1;
        _data = new bytes(31);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.getSwapInLegacyLB(address(this), pair, amountOut, swapForY);

        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.getSwapInLegacyLB(address(this), pair, amountOut, swapForY);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.getSwapInLegacyLB(address(this), pair, amountOut, swapForY);
    }

    function test_Fuzz_SwapLegacyLB(bool swapForY, address recipient, uint256 amountX, uint256 amountY) public {
        _case = 0;
        _data = abi.encode(amountX, amountY);

        (uint256 amountOut) = this.swapLegacyLB(address(this), swapForY, recipient);

        assertEq(amountOut, swapForY ? amountY : amountX, "test_Fuzz_SwapLegacyLB::1");

        assertEq(
            _msgData,
            abi.encodeWithSelector(ILegacyLBPair.swap.selector, swapForY, recipient),
            "test_Fuzz_SwapLegacyLB::2"
        );
    }

    function test_Fuzz_Revert_SwapLegacyLB(bool swapForY, address recipient) public {
        _case = 1;
        _data = new bytes(63);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.swapLegacyLB(address(this), swapForY, recipient);

        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.swapLegacyLB(address(this), swapForY, recipient);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.swapLegacyLB(address(this), swapForY, recipient);
    }

    function test_Fuzz_GetSwapInLB(uint256 amountOut, bool swapForY, uint256 amountIn, uint256 amountLeft) public {
        _case = 1;
        _data = abi.encode(amountIn, amountLeft);

        (uint256 amount, uint256 left) = this.getSwapInLB(address(this), amountOut, swapForY);

        assertEq(amount, amountIn, "test_Fuzz_GetSwapInLB::1");
        assertEq(left, amountLeft, "test_Fuzz_GetSwapInLB::2");
    }

    function test_Fuzz_Revert_GetSwapInLB(uint256 amountOut, bool swapForY) public {
        _case = 1;
        _data = new bytes(63);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.getSwapInLB(address(this), amountOut, swapForY);

        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.getSwapInLB(address(this), amountOut, swapForY);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.getSwapInLB(address(this), amountOut, swapForY);
    }

    function test_Fuzz_SwapLB(bool swapForY, address recipient, uint128 amountX, uint128 amountY) public {
        _case = 0;
        _data = abi.encodePacked(amountY, amountX);

        (uint256 amountOut) = this.swapLB(address(this), swapForY, recipient);

        assertEq(amountOut, swapForY ? amountY : amountX, "test_Fuzz_SwapLB::1");

        assertEq(_msgData, abi.encodeWithSelector(ILBPair.swap.selector, swapForY, recipient), "test_Fuzz_SwapLB::2");
    }

    function test_Fuzz_Revert_SwapLB(bool swapForY, address recipient) public {
        _case = 1;
        _data = new bytes(31);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.swapLB(address(this), swapForY, recipient);

        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.swapLB(address(this), swapForY, recipient);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.swapLB(address(this), swapForY, recipient);
    }

    function test_Fuzz_GetSwapInUV3(bool zeroForOne, uint256 amountOut, int256 amount0, int256 amount1) public {
        _case = 2;
        _data =
            abi.encodeWithSelector(RouterAdapter.RouterAdapter__UniswapV3SwapCallbackOnly.selector, amount0, amount1);

        uint256 amount = this.getSwapInUV3(address(this), zeroForOne, amountOut);

        assertEq(amount, zeroForOne ? uint256(amount0) : uint256(amount1), "test_Fuzz_GetSwapInUV3::1");
    }

    function test_Fuzz_Revert_GetSwapInUV3(
        bytes4 selector,
        bool zeroForOne,
        uint256 amountOut,
        int256 amount0,
        int256 amount1
    ) public {
        _case = 1;
        _data =
            abi.encodeWithSelector(RouterAdapter.RouterAdapter__UniswapV3SwapCallbackOnly.selector, amount0, amount1);

        vm.expectRevert(_data);
        this.getSwapInUV3(address(this), zeroForOne, amountOut);

        if (selector == RouterAdapter.RouterAdapter__UniswapV3SwapCallbackOnly.selector) {
            selector = CustomError.selector;
        }

        _case = 2;
        _data = abi.encodeWithSelector(selector, amount0, amount1);

        vm.expectRevert(_data);
        this.getSwapInUV3(address(this), zeroForOne, amountOut);

        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.getSwapInUV3(address(this), zeroForOne, amountOut);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.getSwapInUV3(address(this), zeroForOne, amountOut);
    }

    function test_Fuzz_SwapUV3(
        address tokenIn,
        bool zeroForOne,
        uint256 amountIn,
        int256 amount0,
        int256 amount1,
        address recipient
    ) public {
        _case = 0;
        _data = abi.encode(amount0, amount1);

        (uint256 amount, uint256 actualAmountIn, uint256 hash) =
            this.swapUV3(address(this), recipient, zeroForOne, amountIn, tokenIn);

        unchecked {
            assertEq(amount, zeroForOne ? uint256(-amount1) : uint256(-amount0), "test_Fuzz_SwapUV3::1");
            assertEq(actualAmountIn, zeroForOne ? uint256(amount0) : uint256(amount1), "test_Fuzz_SwapUV3::2");
        }

        assertEq(hash, uint256(keccak256(abi.encode(amount0, amount1, tokenIn))), "test_Fuzz_SwapUV3::3");

        assertEq(
            _msgData,
            abi.encodeWithSelector(
                IUV3Pair.swap.selector,
                recipient,
                zeroForOne,
                amountIn,
                zeroForOne ? PairInteraction.MIN_SWAP_SQRT_RATIO_UV3 : PairInteraction.MAX_SWAP_SQRT_RATIO_UV3,
                abi.encode(tokenIn)
            ),
            "test_Fuzz_SwapUV3::4"
        );
    }

    function test_Fuzz_Revert_SwapUV3(address tokenIn, bool zeroForOne, uint256 amountIn, address recipient) public {
        _case = 1;
        _data = new bytes(63);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.swapUV3(address(this), tokenIn, zeroForOne, amountIn, recipient);

        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.swapUV3(address(this), tokenIn, zeroForOne, amountIn, recipient);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.swapUV3(address(this), tokenIn, zeroForOne, amountIn, recipient);
    }

    function test_Fuzz_GetSwapInTM(uint256 amountOut, bool swapForY, uint256 amountIn, uint256 actualAmountOut)
        public
    {
        amountOut = bound(amountOut, 0, uint256(type(int256).max));
        amountIn = bound(amountIn, 0, uint256(type(int256).max));
        actualAmountOut = bound(actualAmountOut, 0, uint256(type(int256).max));

        _case = 1;
        _data =
            swapForY ? abi.encode(amountIn, -int256(actualAmountOut)) : abi.encode(-int256(actualAmountOut), amountIn);

        (uint256 amountIn_, uint256 actualAmountOut_) = this.getSwapInTM(address(this), amountOut, swapForY);

        assertEq(amountIn_, amountIn + 1, "test_Fuzz_GetSwapInTM::1");
        assertEq(actualAmountOut_, actualAmountOut, "test_Fuzz_GetSwapInTM::2");
    }

    function test_Fuzz_Revert_GetSwapInTM(uint256 amountOut, bool swapForY) public {
        _case = 1;
        _data = new bytes(63);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.getSwapInTM(address(this), amountOut, swapForY);

        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.getSwapInTM(address(this), amountOut, swapForY);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.getSwapInTM(address(this), amountOut, swapForY);
    }

    function test_Fuzz_SwapTM(
        uint256 amountOut,
        bool swapForY,
        uint256 amountIn,
        uint256 actualAmountIn,
        address recipient
    ) public {
        amountOut = bound(amountOut, 0, uint256(type(int256).max));
        amountIn = bound(amountIn, 0, uint256(type(int256).max));
        actualAmountIn = bound(actualAmountIn, 0, uint256(type(int256).max));

        _case = 0;
        _data =
            swapForY ? abi.encode(actualAmountIn, -int256(amountOut)) : abi.encode(-int256(amountOut), actualAmountIn);

        (uint256 amountOut_, uint256 actualAmountIn_) = this.swapTM(address(this), recipient, amountIn, swapForY);

        assertEq(amountOut_, amountOut, "test_Fuzz_SwapTM::1");
        assertEq(actualAmountIn_, actualAmountIn, "test_Fuzz_SwapTM::2");

        assertEq(
            _msgData,
            abi.encodeWithSelector(ITMPair.swap.selector, recipient, amountIn, swapForY, "", address(0)),
            "test_Fuzz_SwapTM::3"
        );
    }

    function test_Fuzz_Revert_SwapTM(uint256 amountOut, bool swapForY, address recipient) public {
        _case = 1;
        _data = new bytes(63);

        vm.expectRevert(PairInteraction.PairInteraction__InvalidReturnData.selector);
        this.swapTM(address(this), recipient, amountOut, swapForY);

        _case = 2;
        _data = abi.encodeWithSelector(CustomError.selector);

        vm.expectRevert(CustomError.selector);
        this.swapTM(address(this), recipient, amountOut, swapForY);

        _data = "Error String";

        vm.expectRevert("Error String");
        this.swapTM(address(this), recipient, amountOut, swapForY);
    }

    // Helper functions

    function getReservesUV2(address pair, bool ordered) external view returns (uint256, uint256) {
        return PairInteraction.getReservesUV2(pair, ordered);
    }

    function swapUV2(address pair, uint256 amount0, uint256 amount1, address recipient) external {
        PairInteraction.swapUV2(pair, amount0, amount1, recipient);
    }

    function getSwapInLegacyLB(address router, address pair, uint256 amountOut, bool zeroForOne)
        external
        view
        returns (uint256)
    {
        return PairInteraction.getSwapInLegacyLB(router, pair, amountOut, zeroForOne);
    }

    function swapLegacyLB(address pair, bool zeroForOne, address recipient) external returns (uint256) {
        return PairInteraction.swapLegacyLB(pair, zeroForOne, recipient);
    }

    function getSwapInLB(address pair, uint256 amountOut, bool zeroForOne) external view returns (uint256, uint256) {
        return PairInteraction.getSwapInLB(pair, amountOut, zeroForOne);
    }

    function swapLB(address pair, bool zeroForOne, address recipient) external returns (uint256) {
        return PairInteraction.swapLB(pair, zeroForOne, recipient);
    }

    function getSwapInUV3(address pair, bool zeroForOne, uint256 amountOut) external returns (uint256) {
        return PairInteraction.getSwapInUV3(pair, zeroForOne, amountOut);
    }

    function swapUV3(address pair, address recipient, bool zeroForOne, uint256 amountIn, address tokenIn)
        external
        returns (uint256 amountOut, uint256 actualAmountIn, uint256 hash)
    {
        return PairInteraction.swapUV3(pair, recipient, zeroForOne, amountIn, tokenIn);
    }

    function getSwapInTM(address pair, uint256 amountOut, bool zeroForOne) external view returns (uint256, uint256) {
        return PairInteraction.getSwapInTM(pair, amountOut, zeroForOne);
    }

    function swapTM(address pair, address recipient, uint256 amountIn, bool swapForY)
        external
        returns (uint256, uint256)
    {
        return PairInteraction.swapTM(pair, recipient, amountIn, swapForY);
    }
}
