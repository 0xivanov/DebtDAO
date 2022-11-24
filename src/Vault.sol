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
    bool public initialized;
    uint8 public collateralizationPercentage;
    uint8 public constant liquidationThreshold = 150;
    uint64 public constant maxOracleFreshness = 1 hours;

    // --- Events---
    event LoanTaken(address debter, uint256 amount);
    event LoanPayed();
    event CollateralIncreased();
    event Log(int256 price, uint256 timestamp);

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
    function takeLoan(Collateral calldata collateral, uint8 desiredCollateralizationPercentage)
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
        updateCollateralPrice();
        uint256 collateralAfterInterest;
        if (collateralizationPercentage < 150) {
            if (ethCollateral > 0) {
                collateralAfterInterest = getCollateralAfterInterest(ethCollateral);
                ethCollateral = 0;
                (bool sent,) = msg.sender.call{value: ethCollateral, gas: 3000}("");
                if (!sent) revert ExternalCallFailed();
            }
            if (factory.weth().balanceOf(address(this)) > 0) {
                uint256 wethCollateral = factory.weth().balanceOf(address(this));
                collateralAfterInterest = getCollateralAfterInterest(wethCollateral);
                factory.weth().transferFrom(address(this), msg.sender, wethCollateral);
            }
            if (factory.wbtc().balanceOf(address(this)) > 0) {
                uint256 wbtcCollateral = factory.wbtc().balanceOf(address(this));
                collateralAfterInterest = getCollateralAfterInterest(wbtcCollateral);
                factory.weth().transferFrom(address(this), msg.sender, wbtcCollateral);
            }
        } else {
            revert CannotLiquidate();
        }
    }

    function increaseCollateral(Collateral calldata collateral) public payable {
        onlyDebter();
        if (totalCollateralInDollars == 0) revert LoanNotInitiated();
        updateCollateralPrice();
        consumeCollateral(collateral);
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

    function initiateLoan(Collateral calldata collateral, uint8 desiredCollateralizationPercentage)
        internal
        returns (uint256 coinsMinted)
    {
        collateralizationPercentage = desiredCollateralizationPercentage;
        consumeCollateral(collateral);
        coinsMinted = (totalCollateralInDollars * 100) / collateralizationPercentage;
        mint(coinsMinted);
        emit Log(0, coinsMinted);
        emit LoanTaken(msg.sender, coinsMinted);
    }

    function increaseLoan(Collateral calldata collateral, uint8 desiredCollateralizationPercentage)
        internal
        returns (uint256 coinsMinted)
    {
        increaseCollateral(collateral);
        if (desiredCollateralizationPercentage > collateralizationPercentage) revert InvalidCollateral();
        coinsMinted = (totalCollateralInDollars * 100) / collateralizationPercentage;
        mint(coinsMinted);

        emit LoanTaken(msg.sender, coinsMinted);
    }

    function consumeCollateral(Collateral calldata collateral) internal {
        if (collateral.ethAmount > 0) {
            ethCollateral += msg.value;
            (, int256 ethPrice,, uint256 timeStamp,) = factory.ethAggregator().latestRoundData();
            emit Log(ethPrice, timeStamp);
            emit Log(ethPrice, block.timestamp);
            if (block.timestamp - timeStamp >= maxOracleFreshness || ethPrice <= 0) revert ChainLinkOracleError();
            totalCollateralInDollars += uint256(ethPrice / 10 ** 8);
        }
        if (collateral.wethAmount > 0) {
            if (!factory.weth().transferFrom(msg.sender, address(this), collateral.wethAmount)) {
                revert ExternalCallFailed();
            }
            (, int256 wethPrice,, uint256 timeStamp,) = factory.ethAggregator().latestRoundData();
            if (block.timestamp - timeStamp >= maxOracleFreshness || wethPrice <= 0) revert ChainLinkOracleError();
            totalCollateralInDollars += uint256(wethPrice / 10 ** 8);
        }
        if (collateral.wbtcAmount > 0) {
            if (!factory.wbtc().transferFrom(msg.sender, address(this), collateral.wbtcAmount)) {
                revert ExternalCallFailed();
            }
            (, int256 wbtcPrice,, uint256 timeStamp,) = factory.wbtcAggregator().latestRoundData();
            if (block.timestamp - timeStamp >= maxOracleFreshness || wbtcPrice <= 0) revert ChainLinkOracleError();
            totalCollateralInDollars += uint256(wbtcPrice / 10 ** 8);
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
        (, int256 wethPrice,, uint256 wethTimeStamp,) = factory.ethAggregator().latestRoundData();
        if (block.timestamp - wethTimeStamp >= maxOracleFreshness || wethPrice <= 0) revert ChainLinkOracleError();
        (, int256 wbtcPrice,, uint256 wbtcTimeStamp,) = factory.wbtcAggregator().latestRoundData();
        if (block.timestamp - wbtcTimeStamp >= maxOracleFreshness || wbtcPrice <= 0) revert ChainLinkOracleError();
        ethCollateralPrice = uint256(ethPrice / 10 ** 8) * ethCollateral;
        wethCollateralPrice = uint256(wethPrice / 10 ** 8) * wethCollateral;
        wbtcCollateralPrice = uint256(wbtcPrice / 10 ** 8) * wbtcCollateral;
        totalCollateralInDollars = ethCollateralPrice + wethCollateralPrice + wbtcCollateralPrice;
        collateralizationPercentage = uint8(totalCollateralInDollars / (debt * 100));
    }

    function getCollateralAfterInterest(uint256 collateral) internal view returns (uint256 collateralAfterInterest) {
        collateralAfterInterest = ((100 - factory.vaultsInterest()) * collateral) / 100;
    }

    function mint(uint256 amount) internal {
        factory.stablecoin().mint(msg.sender, amount);
        debt = debt + amount;
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
