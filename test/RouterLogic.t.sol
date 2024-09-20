// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/RouterLogic.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockTaxToken.sol";
import "./PackedRouteHelper.sol";

contract RouterLogicTest is Test, PackedRouteHelper {
    RouterLogic public routerLogic;

    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token2;
    MockTaxToken public taxToken;

    MockLBPair public lbPair01;
    MockLBPair public lbPair02;
    MockLBPair public lbPair12;
    MockLBPair public lbPair0t;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    bytes public revertData;

    function getSwapIn(address pair, uint256 amountOut, bool swapForY) external view returns (uint256, uint256) {
        (uint256 amountIn, uint256 amountLeft,) = MockLBPair(pair).getSwapIn(uint128(amountOut), swapForY);
        return (amountIn, amountOut - amountLeft);
    }

    fallback() external {
        bytes memory data = revertData;
        if (data.length > 0) {
            assembly {
                revert(add(data, 32), mload(data))
            }
        }

        uint256 cdatasize;

        assembly {
            cdatasize := calldatasize()
        }

        if (cdatasize == 92) {
            address token;
            address to;
            uint256 amount;

            assembly {
                token := shr(96, calldataload(0))
                to := shr(96, calldataload(40))
                amount := calldataload(60)
            }

            MockERC20(token).transfer(to, amount);
        } else {
            data = abi.encode(1e18, 1e18);

            assembly {
                return(add(data, 32), mload(data))
            }
        }
    }

    function setUp() public {
        routerLogic = new RouterLogic(address(this), address(0));

        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 9);
        token2 = new MockERC20("Token2", "T2", 6);
        taxToken = new MockTaxToken("TaxToken", "TT", 18);

        lbPair01 = new MockLBPair();
        lbPair02 = new MockLBPair();
        lbPair12 = new MockLBPair();
        lbPair0t = new MockLBPair();

        lbPair01.setTokens(token0, token1);
        lbPair02.setTokens(token0, token2);
        lbPair12.setTokens(token1, token2);
        lbPair0t.setTokens(token0, taxToken);
    }

    function test_Fuzz_Revert_SwapExactInStartAndVerify(
        address caller,
        uint8 nbToken,
        address tokenIn,
        address tokenOut
    ) public {
        vm.assume(caller != address(this) && tokenIn != tokenOut && tokenIn != address(0) && tokenOut != address(0));

        vm.expectRevert(IRouterLogic.RouterLogic__OnlyRouter.selector);
        vm.prank(caller);
        routerLogic.swapExactIn(address(0), address(0), address(0), address(0), 0, 0, "");

        nbToken = uint8(bound(nbToken, 2, type(uint8).max));

        (bytes memory routes,) = _createRoutes(nbToken, 0);

        vm.expectRevert(IRouterLogic.RouterLogic__ZeroSwap.selector);
        routerLogic.swapExactIn(address(0), address(0), address(0), address(0), 0, 0, routes);

        (routes,) = _createRoutes(nbToken, 1);

        _setToken(routes, PackedRoute.TOKENS_OFFSET, tokenIn);
        _setToken(routes, PackedRoute.TOKENS_OFFSET + PackedRoute.ADDRESS_SIZE * (nbToken - 1), tokenOut);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenIn.selector);
        routerLogic.swapExactIn(address(0), tokenOut, address(0), address(0), 0, 0, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenIn.selector);
        routerLogic.swapExactIn(tokenOut, tokenOut, address(0), address(0), 0, 0, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenOut.selector);
        routerLogic.swapExactIn(tokenIn, address(0), address(0), address(0), 0, 0, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenOut.selector);
        routerLogic.swapExactIn(tokenIn, tokenIn, address(0), address(0), 0, 0, routes);
    }

    function test_Fuzz_Revert_SwapExactOutStartAndVerify(
        address caller,
        uint8 nbToken,
        address tokenIn,
        address tokenOut
    ) public {
        vm.assume(caller != address(this) && tokenIn != tokenOut && tokenIn != address(0) && tokenOut != address(0));

        vm.expectRevert(IRouterLogic.RouterLogic__OnlyRouter.selector);
        vm.prank(caller);
        routerLogic.swapExactOut(address(0), address(0), address(0), address(0), 0, 0, "");

        nbToken = uint8(bound(nbToken, 2, type(uint8).max));

        bytes memory routes = abi.encodePacked(uint8(nbToken), uint8(0), new bytes(PackedRoute.ADDRESS_SIZE * nbToken));

        vm.expectRevert(IRouterLogic.RouterLogic__ZeroSwap.selector);
        routerLogic.swapExactOut(address(0), address(0), address(0), address(0), 0, 0, routes);

        (routes,) = _createRoutes(nbToken, 1);

        _setToken(routes, PackedRoute.TOKENS_OFFSET, tokenIn);
        _setToken(routes, PackedRoute.TOKENS_OFFSET + PackedRoute.ADDRESS_SIZE * (nbToken - 1), tokenOut);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenIn.selector);
        routerLogic.swapExactOut(address(0), tokenOut, address(0), address(0), 0, 0, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenIn.selector);
        routerLogic.swapExactOut(tokenOut, tokenOut, address(0), address(0), 0, 0, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenOut.selector);
        routerLogic.swapExactOut(tokenIn, address(0), address(0), address(0), 0, 0, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidTokenOut.selector);
        routerLogic.swapExactOut(tokenIn, tokenIn, address(0), address(0), 0, 0, routes);
    }

    function test_Revert_SwapExactIn() public {
        vm.expectRevert(IRouterLogic.RouterLogic__InsufficientTokens.selector);
        routerLogic.swapExactIn(address(0), address(0), address(0), address(0), 0, 0, abi.encodePacked(uint16(0)));

        (bytes memory routes, uint256 ptr) = _createRoutes(1, 0);

        vm.expectRevert(IRouterLogic.RouterLogic__InsufficientTokens.selector);
        routerLogic.swapExactIn(address(0), address(0), address(0), address(0), 0, 0, routes);

        (routes, ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(routes, ptr, false);
        ptr = _setToken(routes, ptr, address(token0));
        ptr = _setToken(routes, ptr, address(token1));

        token0.mint(address(this), 1e18);

        _setRoute(routes, ptr, address(token0), address(token1), address(lbPair01), 0.1e4, ZERO_FOR_ONE | LB12_ID);

        vm.expectRevert(IRouterLogic.RouterLogic__ExcessBalanceUnused.selector);
        routerLogic.swapExactIn(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);

        _setRoute(routes, ptr, address(token0), address(token1), address(lbPair01), 1e4, ZERO_FOR_ONE | LB12_ID);

        vm.expectRevert(
            abi.encodeWithSelector(IRouterLogic.RouterLogic__InsufficientAmountOut.selector, 1e18, 1e18 + 1)
        );
        routerLogic.swapExactIn(address(token0), address(token1), alice, bob, 1e18, 1e18 + 1, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactIn(address(token0), address(token1), alice, bob, 0, 0, routes);

        token0.mint(address(this), type(uint192).max);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactIn(address(token0), address(token1), alice, bob, uint256(type(uint128).max) + 1, 0, routes);

        lbPair01.setPrice(0);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactIn(address(token0), address(token1), alice, bob, type(uint128).max, 0, routes);

        lbPair01.setPrice(1e18 + 1);
        lbPair01.setV2_0(true);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactIn(address(token0), address(token1), alice, bob, type(uint128).max, 0, routes);
    }

    function test_Revert_SwapExactOut() public {
        vm.expectRevert(IRouterLogic.RouterLogic__InsufficientTokens.selector);
        routerLogic.swapExactOut(address(0), address(0), address(0), address(0), 0, 0, abi.encodePacked(uint16(0)));

        (bytes memory routes, uint256 ptr) = _createRoutes(1, 0);

        vm.expectRevert(IRouterLogic.RouterLogic__InsufficientTokens.selector);
        routerLogic.swapExactOut(address(0), address(0), address(0), address(0), 0, 0, routes);

        (routes, ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(routes, ptr, false);
        ptr = _setToken(routes, ptr, address(token0));
        ptr = _setToken(routes, ptr, address(token1));

        _setRoute(routes, ptr, address(token0), address(token1), address(lbPair01), 0.1e4, ZERO_FOR_ONE | LB12_ID);

        vm.expectRevert(IRouterLogic.RouterLogic__ExcessBalanceUnused.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);

        _setRoute(routes, ptr, address(token0), address(token1), address(lbPair01), 1e4, ZERO_FOR_ONE | LB12_ID);

        vm.expectRevert(abi.encodeWithSelector(IRouterLogic.RouterLogic__ExceedsMaxAmountIn.selector, 1e18 + 1, 1e18));
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, 1e18 + 1, routes);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 0, 0, routes);

        token0.mint(address(this), type(uint192).max);

        lbPair01.setPrice(0);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactOut(
            address(token0), address(token1), alice, bob, uint256(type(uint128).max) + 1, 0, routes
        );

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, type(uint128).max, 0, routes);

        lbPair01.setPrice(1e18 + 1);
        lbPair01.setV2_0(true);

        vm.expectRevert(IRouterLogic.RouterLogic__InvalidAmount.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, type(uint128).max, 0, routes);

        ptr = _setIsTransferTaxToken(routes, 1, true);
        ptr = _setToken(routes, ptr, address(token0));
        ptr = _setToken(routes, ptr, address(token1));

        vm.expectRevert(IRouterLogic.RouterLogic__TransferTaxNotSupported.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);
    }

    function test_Fuzz_SwapExactInTaxToken(uint256 tax) public {
        tax = bound(tax, 0, 0.99e18);

        (bytes memory routes, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(routes, ptr, true);
        ptr = _setToken(routes, ptr, address(taxToken));
        ptr = _setToken(routes, ptr, address(token0));

        _setRoute(routes, ptr, address(taxToken), address(token0), address(lbPair0t), 1e4, ONE_FOR_ZERO | LB12_ID);

        uint256 amountIn = 1e18;

        taxToken.mint(address(this), amountIn);
        taxToken.setTax(tax);

        uint256 amountOut = amountIn * (1e18 - tax) / 1e18;

        (uint256 totalIn, uint256 totalOut) =
            routerLogic.swapExactIn(address(taxToken), address(token0), alice, bob, amountIn, amountOut, routes);

        assertEq(totalIn, amountIn, "test_Fuzz_SwapExactInTaxToken::1");
        assertEq(totalOut, amountOut, "test_Fuzz_SwapExactInTaxToken::2");
    }

    function test_Fuzz_Revert_InvalidId(uint16 id) public {
        uint16 invalidId = id == 0 ? id : uint16(bound(id, (UV3_ID >> 8) + 1, type(uint8).max) << 8);

        (bytes memory routes, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(routes, ptr, false);
        ptr = _setToken(routes, ptr, address(token0));
        ptr = _setToken(routes, ptr, address(token1));

        _setRoute(routes, ptr, address(token0), address(token1), address(lbPair01), 1e4, ZERO_FOR_ONE | invalidId);

        token0.mint(address(this), 1e18);

        vm.expectRevert(RouterAdapter.RouterAdapter__InvalidId.selector);
        routerLogic.swapExactIn(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);

        vm.expectRevert(RouterAdapter.RouterAdapter__InvalidId.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);
    }

    function test_Revert_InsufficientLBLiquidity() public {
        (bytes memory routes, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(routes, ptr, false);
        ptr = _setToken(routes, ptr, address(token0));
        ptr = _setToken(routes, ptr, address(token1));

        _setRoute(routes, ptr, address(token0), address(token1), address(lbPair01), 1e4, ZERO_FOR_ONE | LB12_ID);

        vm.expectRevert(RouterAdapter.RouterAdapter__InsufficientLBLiquidity.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, type(uint128).max, routes);
    }

    function test_Revert_UniswapV3() public {
        (bytes memory routes, uint256 ptr) = _createRoutes(2, 1);

        ptr = _setIsTransferTaxToken(routes, ptr, false);
        ptr = _setToken(routes, ptr, address(token0));
        ptr = _setToken(routes, ptr, address(token1));

        _setRoute(routes, ptr, address(token0), address(token1), address(this), 1e4, ZERO_FOR_ONE | UV3_ID);

        vm.expectRevert(RouterAdapter.RouterAdapter__InvalidRevertReason.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);

        revertData = new bytes(1);

        vm.expectRevert(RouterAdapter.RouterAdapter__InvalidRevertReason.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);

        revertData = abi.encodeWithSelector(bytes4(0x12345678), int256(0), int256(0));

        vm.expectRevert(RouterAdapter.RouterAdapter__InvalidRevertReason.selector);
        routerLogic.swapExactOut(address(token0), address(token1), alice, bob, 1e18, 1e18, routes);
    }
}

contract MockLBPair {
    MockERC20 public tokenX;
    MockERC20 public tokenY;
    uint256 public price = 1e18;

    uint256 public reserveX;
    uint256 public reserveY;

    bool public v2_0;

    function test() public pure {} // To avoid this contract to be included in coverage

    function setTokens(MockERC20 tokenX_, MockERC20 tokenY_) public {
        tokenX = tokenX_;
        tokenY = tokenY_;
    }

    function setPrice(uint256 price_) public {
        price = price_;
    }

    function setV2_0(bool v2_0_) public {
        v2_0 = v2_0_;
    }

    function getSwapIn(uint128 amountOut, bool swapForY)
        public
        view
        returns (uint256 amountIn, uint256 amountLeft, uint256 fee)
    {
        fee = 1;
        if (swapForY) {
            uint256 maxAmountOut = type(uint96).max > amountOut ? amountOut : type(uint96).max;

            amountIn = (maxAmountOut * price + (1e18 - 1)) / 1e18;
            amountLeft = amountOut - maxAmountOut;
        } else {
            uint256 maxAmountOut = type(uint96).max > amountOut ? amountOut : type(uint96).max;

            amountIn = (maxAmountOut * 1e18 + (price - 1)) / price;
            amountLeft = amountOut - maxAmountOut;
        }
    }

    function swap(bool swapForY, address recipient) public {
        uint256 amountX;
        uint256 amountY;

        if (swapForY) {
            uint256 balance = tokenX.balanceOf(address(this));
            uint256 received = balance - reserveX;
            uint256 toSend = received * price / 1e18;

            reserveX = balance;

            tokenY.mint(recipient, toSend);

            amountX = received;
            amountY = toSend;
        } else {
            uint256 balance = tokenY.balanceOf(address(this));
            uint256 received = balance - reserveY;
            uint256 toSend = received * price / 1e18;

            reserveY = balance;

            tokenX.mint(recipient, toSend);

            amountX = toSend;
            amountY = received;
        }

        if (v2_0) {
            assembly {
                mstore(0, amountX)
                mstore(32, amountY)

                return(0, 64)
            }
        } else {
            require(amountX <= type(uint128).max && amountY <= type(uint128).max, "overflow");

            assembly {
                let v := or(shl(128, amountY), amountX)

                mstore(0, v)
                return(0, 32)
            }
        }
    }
}
