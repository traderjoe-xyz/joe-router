// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {RouterAdapter} from "./RouterAdapter.sol";
import {PackedRoute} from "./libraries/PackedRoute.sol";
import {Flags} from "./libraries/Flags.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IRouterLogic} from "./interfaces/IRouterLogic.sol";

contract RouterLogic is RouterAdapter, IRouterLogic {
    using SafeERC20 for IERC20;

    address private immutable _router;

    uint256 internal constant BPS = 10000;

    constructor(address router, address routerV2_0) RouterAdapter(routerV2_0) {
        _router = router;
    }

    function swapExactIn(
        address tokenIn,
        address tokenOut,
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes calldata routes
    ) external returns (uint256, uint256) {
        (uint256 ptr, uint256 nbTokens, uint256 nbSwaps) = _startAndVerify(routes, tokenIn, tokenOut);

        uint256[] memory balance = new uint256[](nbTokens);

        balance[0] = amountIn;
        uint256 total = amountIn;

        address from_ = from;
        address to_ = to;
        bytes32 value;
        for (uint256 i; i < nbSwaps; i++) {
            (ptr, value) = PackedRoute.next(routes, ptr);

            unchecked {
                total += _swapExactInSingle(routes, balance, from_, to_, value);
            }
        }

        uint256 amountOut = balance[nbTokens - 1];
        if (total != amountOut) revert RouterLogic__ExcessBalanceUnused();

        if (amountOut < amountOutMin) revert RouterLogic__InsufficientAmountOut(amountOut, amountOutMin);

        return (amountIn, amountOut);
    }

    function swapExactOut(
        address tokenIn,
        address tokenOut,
        address from,
        address to,
        uint256 amountInMax,
        uint256 amountOut,
        bytes calldata routes
    ) external payable returns (uint256 totalIn, uint256 totalOut) {
        (uint256 ptr, uint256 nbTokens, uint256 nbSwaps) = _startAndVerify(routes, tokenIn, tokenOut);

        if (PackedRoute.isTransferTax(routes)) revert RouterLogic__TransferTaxNotSupported();

        (uint256 amountIn, uint256[] memory amountsIn) =
            _getAmountsIn(routes, routes.length, nbTokens, nbSwaps, amountOut);

        if (amountIn > amountInMax) revert RouterLogic__ExceedsMaxAmountIn(amountIn, amountInMax);

        bytes32 value;
        address from_ = from;
        address to_ = to;
        for (uint256 i; i < nbSwaps; i++) {
            (ptr, value) = PackedRoute.next(routes, ptr);

            _swapExactOutSingle(routes, nbTokens, from_, to_, value, amountsIn[i]);
        }

        return (amountIn, amountOut);
    }

    function _checkAmount(uint256 amount) private pure {
        if (amount == 0 || amount > type(uint128).max) revert RouterLogic__InvalidAmount();
    }

    function _balanceOf(address token, address account) private view returns (uint256 amount) {
        uint256 success;

        assembly {
            mstore(0, 0x70a08231) // balanceOf(address)
            mstore(32, account)

            success := staticcall(gas(), token, 28, 36, 0, 32)

            success := and(success, gt(returndatasize(), 31))
            amount := mload(0)
        }
    }

    function _startAndVerify(bytes calldata routes, address tokenIn, address tokenOut)
        private
        view
        returns (uint256 ptr, uint256 nbTokens, uint256 nbSwaps)
    {
        if (msg.sender != _router) revert RouterLogic__OnlyRouter();

        (ptr, nbTokens, nbSwaps) = PackedRoute.start(routes);

        if (nbTokens < 2) revert RouterLogic__InsufficientTokens();
        if (nbSwaps == 0) revert RouterLogic__ZeroSwap();

        if (PackedRoute.token(routes, 0) != tokenIn) revert RouterLogic__InvalidTokenIn();
        if (PackedRoute.token(routes, nbTokens - 1) != tokenOut) revert RouterLogic__InvalidTokenOut();
    }

    function _getAmountsIn(bytes calldata routes, uint256 ptr, uint256 nbTokens, uint256 nbSwaps, uint256 amountOut)
        private
        returns (uint256 amountIn, uint256[] memory)
    {
        uint256[] memory amountsIn = new uint256[](nbSwaps);
        uint256[] memory balance = new uint256[](nbTokens);

        balance[nbTokens - 1] = amountOut;
        uint256 total = amountOut;

        bytes32 value;
        for (uint256 i = nbSwaps; i > 0;) {
            (ptr, value) = PackedRoute.previous(routes, ptr);

            (address pair, uint256 percent, uint256 flags, uint256 tokenOutId, uint256 tokenInId) =
                PackedRoute.decode(value);

            uint256 amount = balance[tokenInId] * percent / BPS;
            balance[tokenInId] -= amount;

            _checkAmount(amount);
            amountIn = _getAmountIn(pair, flags, amount);
            balance[tokenOutId] += amountIn;
            _checkAmount(amountIn);

            amountsIn[--i] = amountIn;

            unchecked {
                total += amountIn - amount;
            }
        }

        amountIn = balance[0];
        if (total != amountIn) revert RouterLogic__ExcessBalanceUnused();

        return (amountIn, amountsIn);
    }

    function _swapExactInSingle(
        bytes calldata routes,
        uint256[] memory balance,
        address from,
        address to,
        bytes32 value
    ) private returns (uint256) {
        (address pair, uint256 percent, uint256 flags, uint256 tokenInId, uint256 tokenOutId) =
            PackedRoute.decode(value);

        uint256 amountIn = balance[tokenInId] * percent / BPS;
        balance[tokenInId] -= amountIn;

        (address tokenIn, uint256 actualAmountIn) =
            _transfer(routes, tokenInId, from, Flags.callback(flags) ? address(this) : pair, amountIn);

        address recipient = tokenOutId == balance.length - 1 ? to : address(this);

        _checkAmount(actualAmountIn);
        uint256 amountOut = _swap(pair, tokenIn, actualAmountIn, recipient, flags);
        _checkAmount(amountOut);

        balance[tokenOutId] += amountOut;

        unchecked {
            return amountOut - amountIn;
        }
    }

    function _swapExactOutSingle(
        bytes calldata routes,
        uint256 nbTokens,
        address from,
        address to,
        bytes32 value,
        uint256 amountIn
    ) private {
        (address pair,, uint256 flags, uint256 tokenInId, uint256 tokenOutId) = PackedRoute.decode(value);

        (address tokenIn, uint256 actualAmountIn) =
            _transfer(routes, tokenInId, from, Flags.callback(flags) ? address(this) : pair, amountIn);

        address recipient = tokenOutId == nbTokens - 1 ? to : address(this);

        _swap(pair, tokenIn, actualAmountIn, recipient, flags);
    }

    function _transfer(bytes calldata routes, uint256 tokenId, address from, address to, uint256 amount)
        private
        returns (address, uint256)
    {
        address token = PackedRoute.token(routes, tokenId);

        if (tokenId == 0) {
            bool isTransferTax = PackedRoute.isTransferTax(routes);

            uint256 balance = isTransferTax ? _balanceOf(token, to) : 0;
            IRouter(_router).transfer(token, from, to, amount);
            amount = isTransferTax ? _balanceOf(token, to) - balance : amount;
        } else if (to != address(this)) {
            IERC20(token).safeTransfer(to, amount);
        }

        return (token, amount);
    }
}
