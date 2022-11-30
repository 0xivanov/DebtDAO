// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "openzeppelin/proxy/Clones.sol";
import "solmate/tokens/ERC20.sol";
import {IVault} from "src/interface/IVault.sol";
import {AggregatorV3Interface} from "src/interface/AggregatorInterfaces.sol";
import {StableCoin} from "src/Stablecoin.sol";

contract VaultFactory {
    //feed
    AggregatorV3Interface public btcAggregator;
    AggregatorV3Interface public ethAggregator;
    //auth
    address public owner;
    //impl
    address public immutable vaultImplementation;
    //global interest
    uint8 public vaultsInterest;
    //tokens
    StableCoin public stablecoin;
    ERC20 public weth;
    ERC20 public wbtc;
    //vaults
    mapping(address => address) public debterToVault;

    event VaultCreated(address indexed debter, address vaultAddress);

    constructor(
        uint8 _interest,
        address _vaultImplementation,
        address _weth,
        address _wbtc,
        address _btcAggregator,
        address _ethAggregator
    ) {
        owner = msg.sender;
        vaultsInterest = _interest;
        vaultImplementation = _vaultImplementation;
        weth = ERC20(_weth);
        wbtc = ERC20(_wbtc);
        btcAggregator = AggregatorV3Interface(_btcAggregator);
        ethAggregator = AggregatorV3Interface(_ethAggregator);
        stablecoin = new StableCoin("mock", "mock", address(this));
    }

    function createVault() public returns (address vault) {
        vault = Clones.clone(vaultImplementation);
        IVault(vault).initialize(msg.sender);
        stablecoin.addVault(vault);
    }
}
