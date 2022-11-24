// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "src/interface/IVault.sol";
import "src/Vault.sol";
import "test/utils/Vault.utils.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {StableCoin} from "src/Stablecoin.sol";
import {MockERC20} from "test/mock/MockERC20.sol";
import {MockPriceFeed} from "test/mock/MockPriceFeed.sol";

contract VaultTest is Test {
    address public deployer;
    address public user;
    MockERC20 weth;
    MockERC20 wbtc; sdfasdf
    MockPriceFeed wethFeed;
    MockPriceFeed wbtcFeed;
    Vault vault;
    VaultUtils utils = new VaultUtils();
    IVault vaultClone;
    StableCoin stablecoin;
    VaultFactory factory;

    function setUp() public {
        {
            deployer = vm.addr(1);
            user = vm.addr(1);
        }
        {
            vm.prank(deployer);
            weth = new MockERC20("weth", "weth");
            wbtc = new MockERC20("wbtc", "wbtc");
            wethFeed = new MockPriceFeed();
            wethFeed.setDecimals(18);
            wethFeed.setTimestamp(block.timestamp);
            wethFeed.setLatestAnswer(int256(100000000000));
            wbtcFeed = new MockPriceFeed();
            wbtcFeed.setDecimals(18);
            wbtcFeed.setTimestamp(block.timestamp);
            wbtcFeed.setLatestAnswer(int256(1500000000000));
            vault = new Vault();
            factory =
            new VaultFactory(3, address(vault), address(weth), address(wbtc), address(wbtcFeed), address(wethFeed), address(wethFeed));
            stablecoin = StableCoin(factory.stablecoin());
        }
        {
            vm.startPrank(user);
            vaultClone = IVault(factory.createVault());
            vm.deal(user, 100 ether);
            weth.mint(100 ether);
            wbtc.mint(100 ether);
            ERC20(weth).approve(address(vaultClone), type(uint256).max);
            ERC20(wbtc).approve(address(vaultClone), type(uint256).max);
        }
    }

    function testTakeLoan() public {
        vaultClone.takeLoan{value: 1 ether}(Collateral(1 ether, 1 ether, 1 ether), 200);
        assertEq(vaultClone.ethCollateral(), 1 ether);
        assertEq(weth.balanceOf(address(vaultClone)), 1 ether);
        assertEq(wbtc.balanceOf(address(vaultClone)), 1 ether);
        console.log(vaultClone.debt());
    }

    function testInitializer() public {
        vm.expectRevert(AlreadyInitialized.selector);
        vault.initialize(address(this));
    }
}
