// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "solmate/tokens/ERC20.sol";
import "openzeppelin/utils/Strings.sol";
import {AggregatorV3Interface} from "src/interface/AggregatorInterfaces.sol";
import {StableCoin} from "src/Stablecoin.sol";
import {VaultFactory} from "src/VaultFactory.sol";

struct Collateral {
    uint256 ethAmount;
    uint256 wethAmount;
    uint256 wbtcAmount;
}

interface IVault {
    function debter() external returns (address);
    function factory() external returns (VaultFactory);
    //vault metrics
    function ethCollateral() external returns (uint256);
    function totalCollateralInDollars() external returns (uint256);
    function debt() external returns (uint256);
    function initialized() external returns (bool);
    function collateralizationPercentage() external returns (uint8);
    function liquidationThreshold() external returns (uint8);
    function maxOracleFreshness() external returns (uint64);
    function initialize(address _debter) external;

    function takeLoan(Collateral memory collateral, uint8 collateralizationPercentage)
        external
        payable
        returns (uint256);
    function payLoan() external;
    function increaseCollateral(Collateral calldata collateral) external payable;
    function liquidate() external;
}
