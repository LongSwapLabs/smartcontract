// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC314.sol";

contract X314 is ERC314 {
    uint256 private _totalSupply = 21_000_000 * 10 ** 18;

    constructor() ERC314("X-314", "X314", _totalSupply, 20 * 2, 2, 2) {}
}
