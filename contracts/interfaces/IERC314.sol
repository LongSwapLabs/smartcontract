// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC314 {
    function setLastTransaction(
        address[] memory accounts,
        uint32 _block
    ) external;
}
