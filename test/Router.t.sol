// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/Router.sol";
import "../src/RouterLogic.sol";
import "./mocks/MockERC20.sol";
import "./mocks/WNative.sol";
import "./mocks/MockTaxToken.sol";

contract RouterTest is Test {
    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token2;
    WNative public wnative;
    MockTaxToken public taxToken;

    Router public router;
    MockRouterLogic public routerLogic;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 9);
        token2 = new MockERC20("Token2", "T2", 6);

        wnative = new WNative();

        taxToken = new MockTaxToken("TaxToken", "TT", 18);
        taxToken.setTax(0.5e18); // 50%

        routerLogic = new MockRouterLogic();
        router = new Router(address(wnative), address(this));

        router.updateRouterLogic(address(routerLogic), true);

        vm.label(address(router), "Router");
        vm.label(address(routerLogic), "RouterLogic");
        vm.label(address(token0), "Token0");
        vm.label(address(token1), "Token1");
        vm.label(address(token2), "Token2");
        vm.label(address(wnative), "WNative");
    }

    function test_Constructor() public {
        assertEq(address(router.WNATIVE()), address(wnative), "test_Constructor::1");
        assertEq(router.owner(), address(this), "test_Constructor::2");

        vm.expectRevert(IRouter.Router__InvalidWnative.selector);
        new Router(address(0), address(this));
    }

    function test_Fuzz_UpdateLogic(address logic) public {
        vm.assume(logic != address(routerLogic));

        assertEq(router.getTrustedLogicLength(), 1, "test_Fuzz_UpdateLogic::1");
        assertEq(router.getTrustedLogicAt(0), address(routerLogic), "test_Fuzz_UpdateLogic::2");

        router.updateRouterLogic(address(logic), true);

        assertEq(router.getTrustedLogicLength(), 2, "test_Fuzz_UpdateLogic::3");
        assertEq(router.getTrustedLogicAt(0), address(routerLogic), "test_Fuzz_UpdateLogic::4");
        assertEq(router.getTrustedLogicAt(1), address(logic), "test_Fuzz_UpdateLogic::5");

        router.updateRouterLogic(address(routerLogic), false);

        assertEq(router.getTrustedLogicLength(), 1, "test_Fuzz_UpdateLogic::6");
        assertEq(router.getTrustedLogicAt(0), address(logic), "test_Fuzz_UpdateLogic::7");

        router.updateRouterLogic(address(logic), false);

        assertEq(router.getTrustedLogicLength(), 0, "test_Fuzz_UpdateLogic::8");
    }

    function test_Fuzz_Revert_UpdateLogic(address logic0, address logic1) public {
        vm.assume(logic0 != address(routerLogic) && logic1 != address(routerLogic) && logic0 != logic1);

        router.updateRouterLogic(address(logic0), true);

        vm.expectRevert(abi.encodeWithSelector(IRouter.Router__LogicAlreadyAdded.selector, address(logic0)));
        router.updateRouterLogic(address(logic0), true);

        router.updateRouterLogic(address(logic1), true);

        vm.expectRevert(abi.encodeWithSelector(IRouter.Router__LogicAlreadyAdded.selector, address(logic1)));
        router.updateRouterLogic(address(logic1), true);

        router.updateRouterLogic(address(logic0), false);

        vm.expectRevert(abi.encodeWithSelector(IRouter.Router__LogicNotFound.selector, address(logic0)));
        router.updateRouterLogic(address(logic0), false);

        router.updateRouterLogic(address(logic1), false);

        vm.expectRevert(abi.encodeWithSelector(IRouter.Router__LogicNotFound.selector, address(logic1)));
        router.updateRouterLogic(address(logic1), false);
    }

    function test_Fuzz_Revert_Transfer(address token, address from, address to, uint256 amount) public {
        vm.expectRevert(RouterLib.RouterLib__ZeroAmount.selector);
        RouterLib.transfer(address(router), token, from, to, 0);

        amount = bound(amount, 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(RouterLib.RouterLib__InsufficientAllowance.selector, 0, amount));
        RouterLib.transfer(address(router), token, from, to, amount);
    }

    function test_Fuzz_SwapExactInTokenToToken(uint256 amountIn, uint256 amountOutMin) public {
        amountIn = bound(amountIn, 1, type(uint256).max);
        amountOutMin = bound(amountOutMin, 1, type(uint256).max);

        bytes memory route = abi.encode(amountIn, amountOutMin);

        token0.mint(alice, amountIn);

        vm.startPrank(alice);
        token0.approve(address(router), amountIn);
        router.swapExactIn(
            address(routerLogic), address(token0), address(token1), amountIn, amountOutMin, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(token0.balanceOf(address(routerLogic)), amountIn, "test_Fuzz_SwapExactInTokenToToken::1");
        assertEq(token1.balanceOf(bob), amountOutMin, "test_Fuzz_SwapExactInTokenToToken::2");
    }

    function test_Fuzz_SwapExactInWNativeToToken(uint256 amountIn, uint256 amountOutMin) public {
        amountIn = bound(amountIn, 1, 100e18);
        amountOutMin = bound(amountOutMin, 1, type(uint256).max);

        bytes memory route = abi.encode(amountIn, amountOutMin);

        wnative.deposit{value: amountIn}();
        wnative.transfer(alice, amountIn);

        vm.startPrank(alice);
        wnative.approve(address(router), amountIn);
        router.swapExactIn(
            address(routerLogic), address(wnative), address(token1), amountIn, amountOutMin, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(wnative.balanceOf(address(routerLogic)), amountIn, "test_Fuzz_SwapExactInWNativeToToken::1");
        assertEq(token1.balanceOf(bob), amountOutMin, "test_Fuzz_SwapExactInWNativeToToken::2");
    }

    function test_Fuzz_SwapExactInNativeToToken(uint256 amountIn, uint256 amountOutMin) public {
        amountIn = bound(amountIn, 1, 100e18);
        amountOutMin = bound(amountOutMin, 1, type(uint256).max);

        bytes memory route = abi.encode(amountIn, amountOutMin);

        payable(alice).transfer(amountIn);

        vm.startPrank(alice);
        router.swapExactIn{value: amountIn}(
            address(routerLogic), address(0), address(token1), amountIn, amountOutMin, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(wnative.balanceOf(address(routerLogic)), amountIn, "test_Fuzz_SwapExactInNativeToToken::1");
        assertEq(token1.balanceOf(bob), amountOutMin, "test_Fuzz_SwapExactInNativeToToken::2");
    }

    function test_Fuzz_SwapExactInTokenToWnative(uint256 amountIn, uint256 amountOutMin) public {
        amountIn = bound(amountIn, 1, type(uint256).max);
        amountOutMin = bound(amountOutMin, 1, 100e18);

        bytes memory route = abi.encode(amountIn, amountOutMin);

        token0.mint(alice, amountIn);

        wnative.deposit{value: amountOutMin}();
        wnative.transfer(address(routerLogic), amountOutMin);

        vm.startPrank(alice);
        token0.approve(address(router), amountIn);
        router.swapExactIn(
            address(routerLogic), address(token0), address(wnative), amountIn, amountOutMin, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(token0.balanceOf(address(routerLogic)), amountIn, "test_Fuzz_SwapExactInTokenToWnative::1");
        assertEq(wnative.balanceOf(bob), amountOutMin, "test_Fuzz_SwapExactInTokenToWnative::2");
    }

    function test_Fuzz_SwapExactInTokenToNative(uint256 amountIn, uint256 amountOutMin) public {
        amountIn = bound(amountIn, 1, type(uint256).max);
        amountOutMin = bound(amountOutMin, 1, 100e18);

        bytes memory route = abi.encode(amountIn, amountOutMin);

        token0.mint(alice, amountIn);

        wnative.deposit{value: amountOutMin}();
        wnative.transfer(address(routerLogic), amountOutMin);

        vm.startPrank(alice);
        token0.approve(address(router), amountIn);
        router.swapExactIn(
            address(routerLogic), address(token0), address(0), amountIn, amountOutMin, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(token0.balanceOf(address(routerLogic)), amountIn, "test_Fuzz_SwapExactInTokenToNative::1");
        assertEq(bob.balance, amountOutMin, "test_Fuzz_SwapExactInTokenToNative::2");
    }

    function test_Fuzz_SwapExactOutTokenToToken(uint256 amountOut, uint256 amountInMax) public {
        amountOut = bound(amountOut, 1, type(uint256).max);
        amountInMax = bound(amountInMax, 1, type(uint256).max);

        bytes memory route = abi.encode(amountInMax, amountOut);

        token0.mint(alice, amountInMax);

        vm.startPrank(alice);
        token0.approve(address(router), amountInMax);
        router.swapExactOut(
            address(routerLogic), address(token0), address(token1), amountOut, amountInMax, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(token0.balanceOf(address(routerLogic)), amountInMax, "test_Fuzz_SwapExactOutTokenToToken::1");
        assertEq(token1.balanceOf(bob), amountOut, "test_Fuzz_SwapExactOutTokenToToken::2");
    }

    function test_Fuzz_SwapExactOutWNativeToToken(uint256 amountOut, uint256 amountInMax) public {
        amountOut = bound(amountOut, 1, type(uint256).max);
        amountInMax = bound(amountInMax, 1, 100e18);

        bytes memory route = abi.encode(amountInMax, amountOut);

        wnative.deposit{value: amountInMax}();
        wnative.transfer(alice, amountInMax);

        vm.startPrank(alice);
        wnative.approve(address(router), amountInMax);
        router.swapExactOut(
            address(routerLogic), address(wnative), address(token1), amountOut, amountInMax, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(wnative.balanceOf(address(routerLogic)), amountInMax, "test_Fuzz_SwapExactOutWNativeToToken::1");
        assertEq(token1.balanceOf(bob), amountOut, "test_Fuzz_SwapExactOutWNativeToToken::2");
    }

    function test_Fuzz_SwapExactOutNativeToToken(uint256 amountOut, uint256 amountInMax) public {
        amountOut = bound(amountOut, 1, type(uint256).max);
        amountInMax = bound(amountInMax, 1, 100e18);

        bytes memory route = abi.encode(amountInMax, amountOut);

        payable(alice).transfer(amountInMax);

        vm.startPrank(alice);
        router.swapExactOut{value: amountInMax}(
            address(routerLogic), address(0), address(token1), amountOut, amountInMax, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(wnative.balanceOf(address(routerLogic)), amountInMax, "test_Fuzz_SwapExactOutNativeToToken::1");
        assertEq(token1.balanceOf(bob), amountOut, "test_Fuzz_SwapExactOutNativeToToken::2");
    }

    function test_Fuzz_SwapExactOutTokenToWnative(uint256 amountOut, uint256 amountInMax) public {
        amountOut = bound(amountOut, 1, 100e18);
        amountInMax = bound(amountInMax, 1, type(uint256).max);

        bytes memory route = abi.encode(amountInMax, amountOut);

        token0.mint(alice, amountInMax);

        wnative.deposit{value: amountOut}();
        wnative.transfer(address(routerLogic), amountOut);

        vm.startPrank(alice);
        token0.approve(address(router), amountInMax);
        router.swapExactOut(
            address(routerLogic), address(token0), address(wnative), amountOut, amountInMax, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(token0.balanceOf(address(routerLogic)), amountInMax, "test_Fuzz_SwapExactOutTokenToWnative::1");
        assertEq(wnative.balanceOf(bob), amountOut, "test_Fuzz_SwapExactOutTokenToWnative::2");
    }

    function test_Fuzz_SwapExactOutTokenToNative(uint256 amountOut, uint256 amountInMax) public {
        amountOut = bound(amountOut, 1, 100e18);
        amountInMax = bound(amountInMax, 1, type(uint256).max);

        bytes memory route = abi.encode(amountInMax, amountOut);

        token0.mint(alice, amountInMax);

        wnative.deposit{value: amountOut}();
        wnative.transfer(address(routerLogic), amountOut);

        vm.startPrank(alice);
        token0.approve(address(router), amountInMax);
        router.swapExactOut(
            address(routerLogic), address(token0), address(0), amountOut, amountInMax, bob, block.timestamp, route
        );
        vm.stopPrank();

        assertEq(token0.balanceOf(address(routerLogic)), amountInMax, "test_Fuzz_SwapExactOutTokenToNative::1");
        assertEq(bob.balance, amountOut, "test_Fuzz_SwapExactOutTokenToNative::2");
    }

    function test_Revert_SwapExactIn() public {
        vm.expectRevert(IRouter.Router__InvalidTo.selector);
        router.swapExactIn(
            address(routerLogic), address(0), address(0), 0, 0, address(0), block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__InvalidTo.selector);
        router.swapExactIn(
            address(routerLogic), address(0), address(0), 0, 0, address(router), block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__DeadlineExceeded.selector);
        router.swapExactIn(address(routerLogic), address(0), address(0), 0, 0, bob, block.timestamp - 1, new bytes(0));

        vm.expectRevert(IRouter.Router__ZeroAmount.selector);
        router.swapExactIn(
            address(routerLogic), address(token0), address(0), 0, 0, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__ZeroAmount.selector);
        router.swapExactIn(
            address(routerLogic), address(token0), address(0), 1, 0, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__ZeroAmount.selector);
        router.swapExactIn(
            address(routerLogic), address(token0), address(0), 0, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactIn(
            address(routerLogic), address(token0), address(token0), 1, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactIn{value: 1}(
            address(routerLogic), address(0), address(0), 1, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactIn(
            address(routerLogic), address(wnative), address(0), 1, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactIn{value: 1}(
            address(routerLogic), address(0), address(wnative), 1, 1, alice, block.timestamp, new bytes(0)
        );

        token0.mint(alice, 10e18);

        wnative.deposit{value: 1e18}();
        wnative.transfer(address(routerLogic), 1e18);

        bytes memory route = abi.encode(10e18, 1e18);

        vm.startPrank(alice);
        token0.approve(address(router), 10e18);
        vm.expectRevert(TokenLib.TokenLib__NativeTransferFailed.selector);
        router.swapExactIn(
            address(routerLogic), address(token0), address(0), 10e18, 1e18, address(this), block.timestamp, route
        );
        vm.stopPrank();
    }

    function test_Revert_SwapExactOut() public {
        vm.expectRevert(IRouter.Router__InvalidTo.selector);
        router.swapExactOut(
            address(routerLogic), address(0), address(0), 0, 0, address(0), block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__InvalidTo.selector);
        router.swapExactOut(
            address(routerLogic), address(0), address(0), 0, 0, address(router), block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__DeadlineExceeded.selector);
        router.swapExactOut(address(routerLogic), address(0), address(0), 0, 0, bob, block.timestamp - 1, new bytes(0));

        vm.expectRevert(IRouter.Router__ZeroAmount.selector);
        router.swapExactOut(
            address(routerLogic), address(token0), address(0), 0, 0, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__ZeroAmount.selector);
        router.swapExactOut(
            address(routerLogic), address(token0), address(0), 1, 0, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__ZeroAmount.selector);
        router.swapExactOut(
            address(routerLogic), address(token0), address(0), 0, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactOut(
            address(routerLogic), address(token0), address(token0), 1, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactOut{value: 1}(
            address(routerLogic), address(0), address(0), 1, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactOut(
            address(routerLogic), address(wnative), address(0), 1, 1, alice, block.timestamp, new bytes(0)
        );

        vm.expectRevert(IRouter.Router__IdenticalTokens.selector);
        router.swapExactOut{value: 1}(
            address(routerLogic), address(0), address(wnative), 1, 1, alice, block.timestamp, new bytes(0)
        );

        token0.mint(alice, 10e18);

        wnative.deposit{value: 1e18}();
        wnative.transfer(address(routerLogic), 1e18);

        bytes memory route = abi.encode(10e18, 1e18);

        vm.startPrank(alice);
        token0.approve(address(router), 10e18);
        vm.expectRevert(TokenLib.TokenLib__NativeTransferFailed.selector);
        router.swapExactOut(
            address(routerLogic), address(token0), address(0), 1e18, 10e18, address(this), block.timestamp, route
        );
        vm.stopPrank();
    }

    function test_Fuzz_Revert_SwapExactIn(uint256 amountIn, uint256 amountOutMin) public {
        amountIn = bound(amountIn, 1, type(uint256).max - 1);
        amountOutMin = bound(amountOutMin, 1, type(uint256).max);

        token0.mint(alice, amountIn);

        bytes memory route = abi.encode(amountIn + 1, amountOutMin);

        vm.startPrank(alice);
        token0.approve(address(router), amountIn);
        vm.expectRevert(
            abi.encodeWithSelector(RouterLib.RouterLib__InsufficientAllowance.selector, amountIn, amountIn + 1)
        );
        router.swapExactIn(
            address(routerLogic), address(token0), address(token1), amountIn, amountOutMin, bob, block.timestamp, route
        );
        vm.stopPrank();

        route = abi.encode(amountIn, amountOutMin - 1);

        vm.startPrank(alice);
        token0.approve(address(router), amountIn);
        vm.expectRevert(
            abi.encodeWithSelector(IRouter.Router__InsufficientOutputAmount.selector, amountOutMin - 1, amountOutMin)
        );
        router.swapExactIn(
            address(routerLogic), address(token0), address(token1), amountIn, amountOutMin, bob, block.timestamp, route
        );
        vm.stopPrank();

        route = abi.encode(amountIn, amountOutMin - 1, amountIn, amountOutMin);

        vm.startPrank(alice);
        token0.approve(address(router), amountIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRouter.Router__InsufficientAmountReceived.selector, 0, amountOutMin - 1, amountOutMin
            )
        );
        router.swapExactIn(
            address(routerLogic), address(token0), address(token1), amountIn, amountOutMin, bob, block.timestamp, route
        );

        route = abi.encode(amountIn, amountOutMin);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRouter.Router__InsufficientAmountReceived.selector, 0, amountOutMin / 2, amountOutMin
            )
        );
        router.swapExactIn(
            address(routerLogic),
            address(token0),
            address(taxToken),
            amountIn,
            amountOutMin,
            bob,
            block.timestamp,
            route
        );
        vm.stopPrank();

        router.updateRouterLogic(address(routerLogic), false);

        vm.expectRevert(abi.encodeWithSelector(IRouter.Router__UntrustedLogic.selector, address(routerLogic)));
        router.swapExactIn(
            address(routerLogic), address(token0), address(token1), amountIn, amountOutMin, bob, block.timestamp, route
        );
    }

    function test_Fuzz_Revert_SwapExactOut(uint256 amountOut, uint256 amountInMax) public {
        amountOut = bound(amountOut, 1, type(uint256).max);
        amountInMax = bound(amountInMax, 1, type(uint256).max - 1);

        token0.mint(alice, amountInMax);

        bytes memory route = abi.encode(amountInMax + 1, amountOut);

        vm.startPrank(alice);
        token0.approve(address(router), amountInMax);
        vm.expectRevert(
            abi.encodeWithSelector(RouterLib.RouterLib__InsufficientAllowance.selector, amountInMax, amountInMax + 1)
        );
        router.swapExactOut(
            address(routerLogic), address(token0), address(token1), amountOut, amountInMax, bob, block.timestamp, route
        );
        vm.stopPrank();

        route = abi.encode(amountInMax, amountOut, amountInMax + 1, amountOut);

        route = abi.encode(amountInMax, amountOut - 1);

        vm.startPrank(alice);
        token0.approve(address(router), amountInMax);
        vm.expectRevert(
            abi.encodeWithSelector(IRouter.Router__InsufficientOutputAmount.selector, amountOut - 1, amountOut)
        );
        router.swapExactOut(
            address(routerLogic), address(token0), address(token1), amountOut, amountInMax, bob, block.timestamp, route
        );
        vm.stopPrank();

        route = abi.encode(amountInMax, amountOut - 1, amountInMax, amountOut);

        vm.startPrank(alice);
        token0.approve(address(router), amountInMax);
        vm.expectRevert(
            abi.encodeWithSelector(IRouter.Router__InsufficientAmountReceived.selector, 0, amountOut - 1, amountOut)
        );
        router.swapExactOut(
            address(routerLogic), address(token0), address(token1), amountOut, amountInMax, bob, block.timestamp, route
        );

        route = abi.encode(amountInMax, amountOut);

        vm.expectRevert(
            abi.encodeWithSelector(IRouter.Router__InsufficientAmountReceived.selector, 0, amountOut / 2, amountOut)
        );
        router.swapExactIn(
            address(routerLogic),
            address(token0),
            address(taxToken),
            amountInMax,
            amountOut,
            bob,
            block.timestamp,
            route
        );
        vm.stopPrank();

        router.updateRouterLogic(address(routerLogic), false);

        vm.expectRevert(abi.encodeWithSelector(IRouter.Router__UntrustedLogic.selector, address(routerLogic)));
        router.swapExactOut(
            address(routerLogic), address(token0), address(token1), amountOut, amountInMax, bob, block.timestamp, route
        );
    }

    function test_Revert_Router() public {
        vm.expectRevert(IRouter.Router__OnlyWnative.selector);
        payable(address(router)).transfer(1);
    }
}

contract MockRouterLogic is IRouterLogic {
    function swapExactIn(
        address tokenIn,
        address tokenOut,
        uint256,
        uint256,
        address from,
        address to,
        bytes calldata route
    ) external returns (uint256 totalIn, uint256 totalOut) {
        (totalIn, totalOut) = abi.decode(route, (uint256, uint256));

        RouterLib.transfer(msg.sender, tokenIn, from, address(this), totalIn);

        MockERC20(tokenOut).mint(to, totalOut);

        if (route.length >= 128) return abi.decode(route[64:], (uint256, uint256));
    }

    function swapExactOut(
        address tokenIn,
        address tokenOut,
        uint256,
        uint256,
        address from,
        address to,
        bytes calldata route
    ) external returns (uint256 totalIn, uint256 totalOut) {
        (totalIn, totalOut) = abi.decode(route, (uint256, uint256));

        RouterLib.transfer(msg.sender, tokenIn, from, address(this), totalIn);

        MockERC20(tokenOut).mint(to, totalOut);

        if (route.length >= 128) return abi.decode(route[64:], (uint256, uint256));
    }

    function sweep(address, address, uint256) external {}
}
