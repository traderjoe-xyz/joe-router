// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITMPairV2 {
    error InvalidRatiosOrder();
    error InvalidRatios();
    error AmountsOverflow();
    error LiquiditiesZero();
    error AlreadyInitialized();
    error SameTokens();
    error InvalidFee();
    error ZeroDeltaAmount();
    error ReentrantCall();
    error InsufficientBalance0();
    error InsufficientBalance1();
    error InvalidSqrtRatioLimit();

    event Swap(
        address indexed sender,
        address indexed to,
        int256 amount0,
        int256 amount1,
        uint256 feeAmountIn,
        uint256 feeAmount1,
        uint256 sqrtRatioX96
    );

    function initialize(address token0, address token1, uint256 fee) external returns (bool);

    function getFactory() external view returns (address);

    function getLiquidities() external view returns (uint256 liquidityA, uint256 liquidityB);

    function getSqrtRatiosBounds()
        external
        view
        returns (uint256 sqrtRatioAX96, uint256 sqrtRatioBX96, uint256 sqrtRatioMaxX96);

    function getBaseToken() external view returns (address);

    function getQuoteToken() external view returns (address);

    function getCurrentSqrtRatio() external view returns (uint256 sqrtRatioX96);

    function getFee() external view returns (uint256);

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);

    function getDeltaAmounts(bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        returns (int256 amount0, int256 amount1);

    function swap(address to, bool zeroForOne, int256 deltaAmount, uint256 sqrtRatioLimitX96)
        external
        returns (int256 amount0, int256 amount1);
}
