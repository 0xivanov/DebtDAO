// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "solmate/tokens/ERC20.sol";
import "openzeppelin/proxy/Clones.sol";
import {IVault, Collateral} from "src/interface/IVault.sol";
import {VaultFactory} from "src/VaultFactory.sol";

error AlreadyInitialized();
error InvalidCollateral();
error ExternalCallFailed();
error InvalidPercentage();
error ChainLinkOracleError();
error Unauthorized();
error LoanNotInitiated();
error CannotLiquidate();

contract Vault is IVault {
    // --- Data ---

    //auth
    address public debter;
    VaultFactory public factory;
    //vault metrics
    uint256 public ethCollateral;
    uint256 public totalCollateralInDollars;
    uint256 public debt;
    uint256 public collateralizationPercentage;
    bool public initialized;
    uint8 public constant liquidationThreshold = 150;
    uint64 public constant maxOracleFreshness = 1 hours;

    // --- Events---
    event LoanTaken(address debter, uint256 amount);
    event LoanPayed();
    event CollateralIncreased();
    event Log(uint256 price, uint256 timestamp);
    event Log2(uint256 collateral);

    constructor() {
        initializer();
    }

    // --- Initializer---
    function initialize(address _debter) external {
        initializer();
        factory = VaultFactory(msg.sender);
        debter = _debter;
    }

    // --- Functions ---
    function takeLoan(Collateral calldata collateral, uint256 desiredCollateralizationPercentage)
        external
        payable
        returns (uint256 coinsMinted)
    {
        onlyDebter();
        if (desiredCollateralizationPercentage < 150 && desiredCollateralizationPercentage > 1000) {
            revert InvalidPercentage();
        }
        if (
            collateral.ethAmount + collateral.wethAmount + collateral.wbtcAmount == 0
                || collateral.ethAmount != msg.value
        ) revert InvalidCollateral();

        if (totalCollateralInDollars == 0) {
            coinsMinted = initiateLoan(collateral, desiredCollateralizationPercentage);
        } else {
            coinsMinted = increaseLoan(collateral, desiredCollateralizationPercentage);
        }
        return coinsMinted;
    }

    function payLoan() external {
        onlyDebter();
        burn(debt);
        uint256 collateralAfterInterest;
        ERC20 weth = factory.weth();
        ERC20 wbtc = factory.wbtc();

        if (ethCollateral > 0) {
            collateralAfterInterest = getCollateralAfterInterest(ethCollateral);
            ethCollateral = 0;
            (bool sent,) = msg.sender.call{value: collateralAfterInterest, gas: 3000}("");
            if (!sent) revert ExternalCallFailed();
        }
        if (weth.balanceOf(address(this)) > 0) {
            uint256 wethCollateral = weth.balanceOf(address(this));
            collateralAfterInterest = getCollateralAfterInterest(wethCollateral);
            weth.transfer(msg.sender, collateralAfterInterest);
        }
        if (wbtc.balanceOf(address(this)) > 0) {
            uint256 wbtcCollateral = wbtc.balanceOf(address(this));
            collateralAfterInterest = getCollateralAfterInterest(wbtcCollateral);
            wbtc.transfer(msg.sender, collateralAfterInterest);
        }
        updateCollateralPrice();
    }

    ///TODO pull the remaining collateral to the factory
    function liquidate() external {
        if (msg.sender == debter) revert Unauthorized();
        burn(debt);
        updateCollateralPrice();
        uint256 collateralAfterInterest;
        if (collateralizationPercentage < 150) {
            if (ethCollateral > 0) {
                collateralAfterInterest = getCollateralAfterInterest(ethCollateral);
                ethCollateral = 0;
                uint256 ethPenalty = (collateralAfterInterest * 20) / 100;
                uint256 ethToReturn = collateralAfterInterest - ethPenalty;
                (bool sent,) = msg.sender.call{value: ethPenalty, gas: 3000}("");
                (bool _sent,) = debter.call{value: ethToReturn, gas: 3000}("");
                if (!_sent || !sent) revert ExternalCallFailed();
            }
            if (factory.weth().balanceOf(address(this)) > 0) {
                uint256 wethCollateral = factory.weth().balanceOf(address(this));
                collateralAfterInterest = getCollateralAfterInterest(wethCollateral);
                uint256 wethPenalty = (collateralAfterInterest * 20) / 100;
                uint256 wethToReturn = collateralAfterInterest - wethPenalty;
                factory.weth().transferFrom(address(this), msg.sender, wethPenalty);
                factory.weth().transferFrom(address(this), debter, wethToReturn);
            }
            if (factory.wbtc().balanceOf(address(this)) > 0) {
                uint256 wbtcCollateral = factory.wbtc().balanceOf(address(this));
                collateralAfterInterest = getCollateralAfterInterest(wbtcCollateral);
                uint256 wbtcPenalty = (collateralAfterInterest * 20) / 100;
                uint256 wbtcToReturn = collateralAfterInterest - wbtcPenalty;
                factory.weth().transferFrom(address(this), msg.sender, wbtcPenalty);
                factory.weth().transferFrom(address(this), debter, wbtcToReturn);
            }
        } else {
            revert CannotLiquidate();
        }
    }

    function initiateLoan(Collateral calldata collateral, uint256 desiredCollateralizationPercentage)
        internal
        returns (uint256 coinsMinted)
    {
        consumeCollateral(collateral);
        updateCollateralPrice();
        coinsMinted = (totalCollateralInDollars * 100) / desiredCollateralizationPercentage;
        mint(coinsMinted);
        if (desiredCollateralizationPercentage != collateralizationPercentage) revert InvalidCollateral();
        emit LoanTaken(msg.sender, coinsMinted);
    }

    function increaseLoan(Collateral calldata collateral, uint256 desiredCollateralizationPercentage)
        internal
        returns (uint256 coinsMinted)
    {
        consumeCollateral(collateral);
        updateCollateralPrice();
        if (desiredCollateralizationPercentage < collateralizationPercentage) {
            coinsMinted = ((totalCollateralInDollars * 100) / desiredCollateralizationPercentage) - debt;
        }
        mint(coinsMinted);
        emit LoanTaken(msg.sender, coinsMinted);
    }

    function consumeCollateral(Collateral calldata collateral) internal {
        if (collateral.ethAmount > 0) {
            ethCollateral += msg.value;
        }
        if (collateral.wethAmount > 0) {
            if (!factory.weth().transferFrom(msg.sender, address(this), collateral.wethAmount)) {
                revert ExternalCallFailed();
            }
        }
        if (collateral.wbtcAmount > 0) {
            if (!factory.wbtc().transferFrom(msg.sender, address(this), collateral.wbtcAmount)) {
                revert ExternalCallFailed();
            }
        }
    }

    function updateCollateralPrice()
        internal
        returns (uint256 ethCollateralPrice, uint256 wethCollateralPrice, uint256 wbtcCollateralPrice)
    {
        uint256 wethCollateral = factory.weth().balanceOf(address(this));
        uint256 wbtcCollateral = factory.wbtc().balanceOf(address(this));
        (, int256 ethPrice,, uint256 ethTimeStamp,) = factory.ethAggregator().latestRoundData();
        if (block.timestamp - ethTimeStamp >= maxOracleFreshness || ethPrice <= 0) revert ChainLinkOracleError();
        (, int256 wbtcPrice,, uint256 wbtcTimeStamp,) = factory.btcAggregator().latestRoundData();
        if (block.timestamp - wbtcTimeStamp >= maxOracleFreshness || wbtcPrice <= 0) revert ChainLinkOracleError();
        ethCollateralPrice = (uint256(ethPrice) * ethCollateral) / 10 ** 8;
        wethCollateralPrice = (uint256(ethPrice) * wethCollateral) / 10 ** 8;
        wbtcCollateralPrice = (uint256(wbtcPrice) * wbtcCollateral) / 10 ** 8;
        totalCollateralInDollars = ethCollateralPrice + wethCollateralPrice + wbtcCollateralPrice;
        updateCollateralizationPercentage();
    }

    function updateCollateralizationPercentage() internal {
        if (debt == 0 || totalCollateralInDollars == 0) collateralizationPercentage = 0;
        else collateralizationPercentage = totalCollateralInDollars * 100 / debt;
    }

    function getCollateralAfterInterest(uint256 collateral) internal view returns (uint256 collateralAfterInterest) {
        collateralAfterInterest = ((100 - factory.vaultsInterest()) * collateral) / 100;
    }

    function mint(uint256 amount) internal {
        factory.stablecoin().mint(msg.sender, amount);
        debt = debt + amount;
        updateCollateralizationPercentage();
    }

    function burn(uint256 amount) internal {
        factory.stablecoin().burn(msg.sender, amount);
        debt = debt - amount;
    }

    function initializer() internal {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
    }

    function onlyDebter() internal view {
        if (msg.sender != debter) revert Unauthorized();
    }
}
