// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/Router.sol";
import "../src/RouterLogic.sol";
import "./PackedRouteHelper.sol";
import "./mocks/MockERC20.sol";
import "./interfaces/ITMPairV2.sol";

contract RouterIntegrationTMV2Test is Test, PackedRouteHelper {
    Router public router;
    RouterLogic public logic;

    address public WAVAX = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
    address public USDC = 0xB6076C93701D6a07266c31066B298AeC6dd65c2d;
    address public TEST = 0xCC91eBE9E3EE3c32F8A34BD3Cde66430B3c66474;

    address public LB2_AVAX_USDC = 0xBf462AA2d456Ec51509a9C7f54DB38e1cA11825f;

    address public TMV2_TEST_AVAX = 0xbfFc7c9b5939686ee5765Db76B0Eb8dED88d7d3C;

    address alice = makeAddr("Alice");

    uint256 minPrice;
    uint256 maxPrice;

    function setUp() public {
        vm.createSelectFork(StdChains.getChain("avalanche_fuji").rpcUrl, 38758068);

        router = new Router(WAVAX, address(this));
        logic = new RouterLogic(address(router), address(0));

        router.updateRouterLogic(address(logic), true);

        (minPrice,, maxPrice) = ITMPairV2(TMV2_TEST_AVAX).getSqrtRatiosBounds();

        vm.label(address(router), "Router");
        vm.label(address(logic), "RouterLogic");
        vm.label(WAVAX, "WAVAX");
        vm.label(USDC, "USDC");
        vm.label(TEST, "TEST");
        vm.label(LB2_AVAX_USDC, "LB2_AVAX_USDC");
        vm.label(TMV2_TEST_AVAX, "TMV2_TEST_AVAX");
    }

    function test_SwapExactInTokenToToken() public {
        uint128 amountIn = 1000e6;

        vm.deal(alice, 0.1e18);
        deal(USDC, alice, amountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(3, 2);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, USDC);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, TEST);

        ptr = _setRoute(route, ptr, USDC, WAVAX, LB2_AVAX_USDC, 1e4, LB12_ID | ONE_FOR_ZERO);
        ptr = _setRoute(route, ptr, WAVAX, TEST, TMV2_TEST_AVAX, 1e4, TMV2_ID | ONE_FOR_ZERO);

        vm.startPrank(alice);
        IERC20(USDC).approve(address(router), amountIn);

        uint256 expectedOut;
        {
            bytes[] memory multiRoutes = new bytes[](3);

            multiRoutes[0] = route;
            multiRoutes[1] = route;

            (, bytes memory data) = address(router).call{value: 0.1e18}(
                abi.encodeWithSelector(
                    IRouter.simulate.selector, logic, USDC, TEST, amountIn, 1, alice, true, multiRoutes
                )
            );

            uint256[] memory values;

            assembly ("memory-safe") {
                values := add(data, 68)
            }

            assertEq(values.length, 3, "test_SwapExactInTokenToToken::1");
            assertEq(values[0], values[1], "test_SwapExactInTokenToToken::2");
            assertEq(values[2], 0, "test_SwapExactInTokenToToken::3");

            expectedOut = values[0];
        }

        (uint256 totalIn, uint256 totalOut) =
            router.swapExactIn{value: 0.1e18}(address(logic), USDC, TEST, amountIn, 1, alice, block.timestamp, route);
        vm.stopPrank();

        assertEq(totalIn, amountIn, "test_SwapExactInTokenToToken::4");
        assertGt(totalOut, 0, "test_SwapExactInTokenToToken::5");
        assertEq(totalOut, expectedOut, "test_SwapExactInTokenToToken::6");
        assertEq(alice.balance, 0.1e18, "test_SwapExactInTokenToToken::7");
        assertEq(IERC20(USDC).balanceOf(alice), 0, "test_SwapExactInTokenToToken::8");
        assertEq(IERC20(TEST).balanceOf(alice), totalOut, "test_SwapExactInTokenToToken::9");
    }

    function test_SwapExactOutTokenToToken() public {
        uint128 amountOut = 1e6;
        uint256 maxAmountIn = 10_000_000e18;

        vm.deal(alice, 0.1e18);
        deal(TEST, alice, maxAmountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(3, 2);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, TEST);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, USDC);

        ptr = _setRoute(route, ptr, TEST, WAVAX, TMV2_TEST_AVAX, 1.0e4, TMV2_ID | ZERO_FOR_ONE);
        ptr = _setRoute(route, ptr, WAVAX, USDC, LB2_AVAX_USDC, 1e4, LB12_ID | ZERO_FOR_ONE);

        vm.startPrank(alice);
        IERC20(TEST).approve(address(router), maxAmountIn);

        uint256 expectedIn;
        {
            bytes[] memory multiRoutes = new bytes[](3);

            multiRoutes[0] = route;
            multiRoutes[1] = route;

            (, bytes memory data) = address(router).call{value: 0.1e18}(
                abi.encodeWithSelector(
                    IRouter.simulate.selector,
                    logic,
                    TEST,
                    USDC,
                    type(uint128).max,
                    amountOut,
                    alice,
                    false,
                    multiRoutes
                )
            );

            uint256[] memory values;

            assembly ("memory-safe") {
                values := add(data, 68)
            }

            assertEq(values.length, 3, "test_SwapExactOutTokenToToken::1");
            assertEq(values[0], values[1], "test_SwapExactOutTokenToToken::2");
            assertEq(values[2], type(uint256).max, "test_SwapExactOutTokenToToken::3");

            expectedIn = values[0];
        }

        (uint256 totalIn, uint256 totalOut) = router.swapExactOut{value: 0.1e18}(
            address(logic), TEST, USDC, amountOut, maxAmountIn, alice, block.timestamp, route
        );
        vm.stopPrank();

        assertLe(totalIn, maxAmountIn, "test_SwapExactOutTokenToToken::4");
        assertEq(totalIn, expectedIn, "test_SwapExactOutTokenToToken::5");
        assertGe(totalOut, amountOut, "test_SwapExactOutTokenToToken::6");
        assertEq(alice.balance, 0.1e18, "test_SwapExactOutTokenToToken::7");
        assertEq(IERC20(TEST).balanceOf(alice), maxAmountIn - totalIn, "test_SwapExactOutTokenToToken::8");
        assertEq(IERC20(USDC).balanceOf(alice), amountOut, "test_SwapExactOutTokenToToken::9");
    }

    function test_SwapExactInNativeToToken() public {
        uint128 amountIn = 1e18;

        vm.deal(alice, amountIn + 0.1e18);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, TEST);

        ptr = _setRoute(route, ptr, WAVAX, TEST, TMV2_TEST_AVAX, 1.0e4, TMV2_ID | ONE_FOR_ZERO);

        vm.prank(alice);
        (uint256 totalIn, uint256 totalOut) = router.swapExactIn{value: amountIn + 0.1e18}(
            address(logic), address(0), TEST, amountIn, 1, alice, block.timestamp, route
        );

        assertEq(totalIn, amountIn, "test_SwapExactInNativeToToken::1");
        assertGt(totalOut, 0, "test_SwapExactInNativeToToken::2");
        assertEq(alice.balance, 0.1e18, "test_SwapExactInNativeToToken::3");
        assertEq(IERC20(TEST).balanceOf(alice), totalOut, "test_SwapExactInNativeToToken::4");
    }

    function test_SwapExactOutNativeToToken() public {
        uint128 amountOut = 1_000_000e18;
        uint256 maxAmountIn = 100e18;

        vm.deal(alice, maxAmountIn + 0.1e18);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, TEST);

        ptr = _setRoute(route, ptr, WAVAX, TEST, TMV2_TEST_AVAX, 1.0e4, TMV2_ID | ONE_FOR_ZERO);

        (, int256 deltaQuote) = ITMPairV2(TMV2_TEST_AVAX).getDeltaAmounts(false, -int128(amountOut), maxPrice);
        (int256 deltaBase,) = ITMPairV2(TMV2_TEST_AVAX).getDeltaAmounts(false, deltaQuote, maxPrice);

        assertGe(uint256(-deltaBase), amountOut, "test_SwapExactOutNativeToToken::1");

        vm.prank(alice);
        (uint256 totalIn, uint256 totalOut) = router.swapExactOut{value: maxAmountIn + 0.1e18}(
            address(logic), address(0), TEST, amountOut, maxAmountIn, alice, block.timestamp, route
        );

        assertLe(totalIn, maxAmountIn, "test_SwapExactOutNativeToToken::3");
        assertGe(totalOut, amountOut, "test_SwapExactOutNativeToToken::4");
        assertEq(alice.balance, maxAmountIn + 0.1e18 - totalIn, "test_SwapExactOutNativeToToken::5");
        assertGe(IERC20(TEST).balanceOf(alice), amountOut, "test_SwapExactOutNativeToToken::6");
    }

    function test_SwapExactInTokenToNative() public {
        uint128 amountIn = 1_000_000e18;

        vm.deal(alice, 0.1e18);
        deal(TEST, alice, amountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, TEST);
        ptr = _setToken(route, ptr, WAVAX);

        ptr = _setRoute(route, ptr, TEST, WAVAX, TMV2_TEST_AVAX, 1.0e4, TMV2_ID | ZERO_FOR_ONE);

        vm.startPrank(alice);
        IERC20(TEST).approve(address(router), amountIn);

        (uint256 totalIn, uint256 totalOut) = router.swapExactIn{value: 0.1e18}(
            address(logic), TEST, address(0), amountIn, 1, alice, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(totalIn, amountIn, "test_SwapExactInTokenToNative::1");
        assertGt(totalOut, 0, "test_SwapExactInTokenToNative::2");
        assertEq(alice.balance, 0.1e18 + totalOut, "test_SwapExactInTokenToNative::3");
        assertEq(IERC20(TEST).balanceOf(alice), 0, "test_SwapExactInTokenToNative::4");
    }

    function test_SwapExactOutTokenToNative() public {
        uint128 amountOut = 0.1e18;
        uint256 maxAmountIn = 10_000_000e18;

        vm.deal(alice, 0.1e18);
        deal(TEST, alice, maxAmountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, TEST);
        ptr = _setToken(route, ptr, WAVAX);

        ptr = _setRoute(route, ptr, TEST, WAVAX, TMV2_TEST_AVAX, 1.0e4, TMV2_ID | ZERO_FOR_ONE);

        vm.startPrank(alice);
        IERC20(TEST).approve(address(router), maxAmountIn);

        (uint256 totalIn, uint256 totalOut) = router.swapExactOut{value: 0.1e18}(
            address(logic), TEST, address(0), amountOut, maxAmountIn, alice, block.timestamp, route
        );
        vm.stopPrank();

        assertLe(totalIn, maxAmountIn, "test_SwapExactOutTokenToNative::1");
        assertGe(totalOut, amountOut, "test_SwapExactOutTokenToNative::2");
        assertEq(alice.balance, 0.1e18 + totalOut, "test_SwapExactOutTokenToNative::3");
        assertEq(IERC20(TEST).balanceOf(alice), maxAmountIn - totalIn, "test_SwapExactOutTokenToNative::4");
    }

    function test_Revert_SwapOutOfLiquidity() public {
        uint128 amountIn = 1e36;

        vm.deal(alice, 1e36 + 0.1e18);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, TEST);

        ptr = _setRoute(route, ptr, WAVAX, TEST, TMV2_TEST_AVAX, 1.0e4, TMV2_ID | ONE_FOR_ZERO);

        vm.prank(alice);
        vm.expectRevert(RouterAdapter.RouterAdapter__InsufficientTMV2Liquidity.selector);
        router.swapExactIn{value: 1e36 + 0.1e18}(
            address(logic), address(0), TEST, amountIn, 1, alice, block.timestamp, route
        );

        vm.prank(alice);
        vm.expectRevert(RouterAdapter.RouterAdapter__InsufficientTMV2Liquidity.selector);
        router.swapExactOut{value: 1e36 + 0.1e18}(
            address(logic), address(0), TEST, amountIn, amountIn, alice, block.timestamp, route
        );
    }
}
