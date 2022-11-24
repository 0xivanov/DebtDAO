// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Collateral} from "src/interface/IVault.sol";

contract VaultUtils {
    function getValidCollateral() external pure returns (Collateral memory) {
        return Collateral(1 ether, 1 ether, 1 ether);
    }
}
