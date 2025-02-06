# [Joe Router Contract](https://github.com/traderjoe-xyz/joe-router)

This repository contains the implementation of a Router contract for swapping tokens using predefined routes. The routes must follow the PackedRoute format. The Router contract interacts with various decentralized exchanges (DEXs) such as Uniswap V2, Uniswap V3, and LFJ (formerly Trader Joe).

## Contracts

### Router.sol

The main Router contract for swapping tokens using predefined routes. It supports both exact input and exact output swaps. The router contract will validate the route and perform the swaps using the `RouterLogic` contract.

### RouterLogic.sol

The RouterLogic contract implements the logic for swapping tokens using a route. It interacts with different DEXs to perform the swaps. The route must be in the PackedRoute format.

### RouterAdapter.sol

The RouterAdapter contract provides helper functions for interacting with different types of pairs, including Uniswap V2, LFJ Legacy Liquidity Book, LFJ Liquidity Book, Uniswap V3 pairs, and LFJ Token Mill pairs.

## Libraries

### TokenLib.sol

Helper library for token operations, such as balanceOf, transfer, transferFrom, wrap, and unwrap.

### RouterLib.sol

Helper library for router operations, such as validateAndTransfer, transfer, and swap.

### PairInteraction.sol

Helper library for interacting with Uniswap V2, LFJ (formerly Trader Joe), and Uniswap V3 pairs.

### PackedRoute.sol

Helper library to decode packed route data. For more information on the PackedRoute format, see the PackedRoute documentation.

### Flags.sol

Helper library for parsing flags received from a packed route.

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## Contact

For any questions or inquiries, please contact the repository owner.
