// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/Router.sol";
import "../src/RouterLogic.sol";
import "./PackedRouteHelper.sol";
import "./mocks/MockERC20.sol";
import "./interfaces/ITMPair.sol";

contract RouterIntegrationTMTest is Test, PackedRouteHelper {
    Router public router;
    RouterLogic public logic;

    address public WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public CHAMP = 0xb0Aa388A35742F2d54A049803BFf49a70EB99659;

    address public TJ1_AVAX_USDC = 0xf4003F4efBE8691B60249E6afbD307aBE7758adb;

    address public LB1_AVAX_USDC = 0xD446eb1660F766d533BeCeEf890Df7A69d26f7d1;

    address public UV3_AVAX_USDC = 0xfAe3f424a0a47706811521E3ee268f00cFb5c45E;

    address public TM_CHAMP_AVAX = 0xE8e45d1866efe193268Ba3820a52717A2645d78C;

    address alice = makeAddr("Alice");

    function setUp() public {
        vm.createSelectFork(StdChains.getChain("avalanche").rpcUrl, 56845529);

        router = new Router(WAVAX, address(this));
        logic = new RouterLogic(address(router), address(0));

        router.updateRouterLogic(address(logic), true);

        vm.label(address(router), "Router");
        vm.label(address(logic), "RouterLogic");
        vm.label(WAVAX, "WAVAX");
        vm.label(USDC, "USDC");
        vm.label(TJ1_AVAX_USDC, "TJ1_AVAX_USDC");
        vm.label(LB1_AVAX_USDC, "LB1_AVAX_USDC");
        vm.label(UV3_AVAX_USDC, "UV3_AVAX_USDC");
    }

    function test_SwapExactInTokenToToken() public {
        uint128 amountIn = 1000e6;

        vm.deal(alice, 0.1e18);
        deal(USDC, alice, amountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(3, 4);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, USDC);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, CHAMP);

        ptr = _setRoute(route, ptr, USDC, WAVAX, TJ1_AVAX_USDC, 0.2e4, TJ1_ID | ONE_FOR_ZERO);
        ptr = _setRoute(route, ptr, USDC, WAVAX, LB1_AVAX_USDC, 0.7e4, LB12_ID | ONE_FOR_ZERO);
        ptr = _setRoute(route, ptr, USDC, WAVAX, UV3_AVAX_USDC, 1e4, UV3_ID | CALLBACK | ONE_FOR_ZERO);
        ptr = _setRoute(route, ptr, WAVAX, CHAMP, TM_CHAMP_AVAX, 1e4, TM_ID | ONE_FOR_ZERO);

        vm.startPrank(alice);
        IERC20(USDC).approve(address(router), amountIn);

        uint256 expectedOut;
        {
            bytes[] memory multiRoutes = new bytes[](3);

            multiRoutes[0] = route;
            multiRoutes[1] = route;

            (, bytes memory data) = address(router).call{value: 0.1e18}(
                abi.encodeWithSelector(
                    IRouter.simulate.selector, logic, USDC, CHAMP, amountIn, 1, alice, true, multiRoutes
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
            router.swapExactIn{value: 0.1e18}(address(logic), USDC, CHAMP, amountIn, 1, alice, block.timestamp, route);
        vm.stopPrank();

        assertEq(totalIn, amountIn, "test_SwapExactInTokenToToken::4");
        assertGt(totalOut, 0, "test_SwapExactInTokenToToken::5");
        assertEq(totalOut, expectedOut, "test_SwapExactInTokenToToken::6");
        assertEq(alice.balance, 0.1e18, "test_SwapExactInTokenToToken::7");
        assertEq(IERC20(USDC).balanceOf(alice), 0, "test_SwapExactInTokenToToken::8");
        assertEq(IERC20(CHAMP).balanceOf(alice), totalOut, "test_SwapExactInTokenToToken::9");
    }

    function test_SwapExactOutTokenToToken() public {
        uint128 amountOut = 1000e6;
        uint256 maxAmountIn = 10_000_000e18;

        vm.deal(alice, 0.1e18);
        deal(CHAMP, alice, maxAmountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(3, 4);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, CHAMP);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, USDC);

        ptr = _setRoute(route, ptr, CHAMP, WAVAX, TM_CHAMP_AVAX, 1.0e4, TM_ID | ZERO_FOR_ONE);
        ptr = _setRoute(route, ptr, WAVAX, USDC, TJ1_AVAX_USDC, 1e4, TJ1_ID | ZERO_FOR_ONE);
        ptr = _setRoute(route, ptr, WAVAX, USDC, LB1_AVAX_USDC, 0.74e4, LB12_ID | ZERO_FOR_ONE);
        ptr = _setRoute(route, ptr, WAVAX, USDC, UV3_AVAX_USDC, 0.24e4, UV3_ID | CALLBACK | ZERO_FOR_ONE);

        vm.startPrank(alice);
        IERC20(CHAMP).approve(address(router), maxAmountIn);

        uint256 expectedIn;
        {
            bytes[] memory multiRoutes = new bytes[](3);

            multiRoutes[0] = route;
            multiRoutes[1] = route;

            (, bytes memory data) = address(router).call{value: 0.1e18}(
                abi.encodeWithSelector(
                    IRouter.simulate.selector,
                    logic,
                    CHAMP,
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
            address(logic), CHAMP, USDC, amountOut, maxAmountIn, alice, block.timestamp, route
        );
        vm.stopPrank();

        assertLe(totalIn, maxAmountIn, "test_SwapExactOutTokenToToken::4");
        assertEq(totalIn, expectedIn, "test_SwapExactOutTokenToToken::5");
        assertGe(totalOut, amountOut, "test_SwapExactOutTokenToToken::6");
        assertEq(alice.balance, 0.1e18, "test_SwapExactOutTokenToToken::7");
        assertEq(IERC20(CHAMP).balanceOf(alice), maxAmountIn - totalIn, "test_SwapExactOutTokenToToken::8");
        assertEq(IERC20(USDC).balanceOf(alice), amountOut, "test_SwapExactOutTokenToToken::9");
    }

    function test_SwapExactInNativeToToken() public {
        uint128 amountIn = 1e18;

        vm.deal(alice, amountIn + 0.1e18);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, CHAMP);

        ptr = _setRoute(route, ptr, WAVAX, CHAMP, TM_CHAMP_AVAX, 1.0e4, TM_ID | ONE_FOR_ZERO);

        vm.prank(alice);
        (uint256 totalIn, uint256 totalOut) = router.swapExactIn{value: amountIn + 0.1e18}(
            address(logic), address(0), CHAMP, amountIn, 1, alice, block.timestamp, route
        );

        assertEq(totalIn, amountIn, "test_SwapExactInNativeToToken::1");
        assertGt(totalOut, 0, "test_SwapExactInNativeToToken::2");
        assertEq(alice.balance, 0.1e18, "test_SwapExactInNativeToToken::3");
        assertEq(IERC20(CHAMP).balanceOf(alice), totalOut, "test_SwapExactInNativeToToken::4");
    }

    function test_SwapExactOutNativeToToken() public {
        uint128 amountOut = 1_000_000e18;
        uint256 maxAmountIn = 100e18;

        vm.deal(alice, maxAmountIn + 0.1e18);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, CHAMP);

        ptr = _setRoute(route, ptr, WAVAX, CHAMP, TM_CHAMP_AVAX, 1.0e4, TM_ID | ONE_FOR_ZERO);

        (, int256 deltaQuote,) = ITMPair(TM_CHAMP_AVAX).getDeltaAmounts(-int128(amountOut), false);
        (int256 deltaBase,,) = ITMPair(TM_CHAMP_AVAX).getDeltaAmounts(deltaQuote, false);

        assertLt(uint256(-deltaBase), amountOut, "test_SwapExactOutNativeToToken::1");

        (, deltaQuote,) = ITMPair(TM_CHAMP_AVAX).getDeltaAmounts(-int128(amountOut), false);
        (deltaBase,,) = ITMPair(TM_CHAMP_AVAX).getDeltaAmounts(deltaQuote + 1, false);

        assertGe(uint256(-deltaBase), amountOut, "test_SwapExactOutNativeToToken::2");

        vm.prank(alice);
        (uint256 totalIn, uint256 totalOut) = router.swapExactOut{value: maxAmountIn + 0.1e18}(
            address(logic), address(0), CHAMP, amountOut, maxAmountIn, alice, block.timestamp, route
        );

        assertLe(totalIn, maxAmountIn, "test_SwapExactOutNativeToToken::3");
        assertGe(totalOut, amountOut, "test_SwapExactOutNativeToToken::4");
        assertEq(alice.balance, maxAmountIn + 0.1e18 - totalIn, "test_SwapExactOutNativeToToken::5");
        assertGe(IERC20(CHAMP).balanceOf(alice), amountOut, "test_SwapExactOutNativeToToken::6");
    }

    function test_SwapExactInTokenToNative() public {
        uint128 amountIn = 1_000_000e18;

        vm.deal(alice, 0.1e18);
        deal(CHAMP, alice, amountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, CHAMP);
        ptr = _setToken(route, ptr, WAVAX);

        ptr = _setRoute(route, ptr, CHAMP, WAVAX, TM_CHAMP_AVAX, 1.0e4, TM_ID | ZERO_FOR_ONE);

        vm.startPrank(alice);
        IERC20(CHAMP).approve(address(router), amountIn);

        (uint256 totalIn, uint256 totalOut) = router.swapExactIn{value: 0.1e18}(
            address(logic), CHAMP, address(0), amountIn, 1, alice, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(totalIn, amountIn, "test_SwapExactInTokenToNative::1");
        assertGt(totalOut, 0, "test_SwapExactInTokenToNative::2");
        assertEq(alice.balance, 0.1e18 + totalOut, "test_SwapExactInTokenToNative::3");
        assertEq(IERC20(CHAMP).balanceOf(alice), 0, "test_SwapExactInTokenToNative::4");
    }

    function test_SwapExactOutTokenToNative() public {
        uint128 amountOut = 1e18;
        uint256 maxAmountIn = 1_000_000e18;

        vm.deal(alice, 0.1e18);
        deal(CHAMP, alice, maxAmountIn);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, CHAMP);
        ptr = _setToken(route, ptr, WAVAX);

        ptr = _setRoute(route, ptr, CHAMP, WAVAX, TM_CHAMP_AVAX, 1.0e4, TM_ID | ZERO_FOR_ONE);

        vm.startPrank(alice);
        IERC20(CHAMP).approve(address(router), maxAmountIn);

        (uint256 totalIn, uint256 totalOut) = router.swapExactOut{value: 0.1e18}(
            address(logic), CHAMP, address(0), amountOut, maxAmountIn, alice, block.timestamp, route
        );
        vm.stopPrank();

        assertLe(totalIn, maxAmountIn, "test_SwapExactOutTokenToNative::1");
        assertGe(totalOut, amountOut, "test_SwapExactOutTokenToNative::2");
        assertEq(alice.balance, 0.1e18 + totalOut, "test_SwapExactOutTokenToNative::3");
        assertEq(IERC20(CHAMP).balanceOf(alice), maxAmountIn - totalIn, "test_SwapExactOutTokenToNative::4");
    }

    function test_Revert_SwapOutOfLiquidity() public {
        uint128 amountIn = 1e36;

        vm.deal(alice, 1e36 + 0.1e18);

        (bytes memory route, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(route, ptr, false);
        ptr = _setToken(route, ptr, WAVAX);
        ptr = _setToken(route, ptr, CHAMP);

        ptr = _setRoute(route, ptr, WAVAX, CHAMP, TM_CHAMP_AVAX, 1.0e4, TM_ID | ONE_FOR_ZERO);

        vm.prank(alice);
        vm.expectRevert(RouterAdapter.RouterAdapter__InsufficientTMLiquidity.selector);
        router.swapExactIn{value: 1e36 + 0.1e18}(
            address(logic), address(0), CHAMP, amountIn, 1, alice, block.timestamp, route
        );

        vm.prank(alice);
        vm.expectRevert(RouterAdapter.RouterAdapter__InsufficientTMLiquidity.selector);
        router.swapExactOut{value: 1e36 + 0.1e18}(
            address(logic), address(0), CHAMP, amountIn, amountIn, alice, block.timestamp, route
        );
    }
}
