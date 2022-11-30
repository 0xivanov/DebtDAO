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
    MockERC20 wbtc;
    MockPriceFeed ethFeed;
    MockPriceFeed btcFeed;
    Vault vault;
    VaultUtils utils = new VaultUtils();
    IVault vaultClone;
    StableCoin stablecoin;
    VaultFactory factory;
    int256 constant ethPrice = 121479000000;
    int256 constant btcPrice = 1647442138012;

    function setUp() public {
        {
            deployer = vm.addr(1);
            user = vm.addr(1);
        }
        {
            vm.prank(deployer);
            weth = new MockERC20("weth", "weth");
            wbtc = new MockERC20("wbtc", "wbtc");
            ethFeed = new MockPriceFeed();
            ethFeed.setTimestamp(block.timestamp);

            ethFeed.setLatestAnswer(int256(ethPrice));
            btcFeed = new MockPriceFeed();
            btcFeed.setTimestamp(block.timestamp);
            btcFeed.setLatestAnswer(int256(btcPrice));
            vault = new Vault();
            factory =
                new VaultFactory(3, address(vault), address(weth), address(wbtc), address(btcFeed), address(ethFeed));
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

    function testHappyPath() public {
        vaultClone.takeLoan{value: 1 ether}(Collateral(1 ether, 1 ether, 1 ether), 200);
        assertEq(vaultClone.ethCollateral(), 1 ether);
        assertEq(weth.balanceOf(address(vaultClone)), 1 ether);
        assertEq(wbtc.balanceOf(address(vaultClone)), 1 ether);
        assertEq(vaultClone.collateralizationPercentage(), 200);

        vaultClone.takeLoan{value: 0.2 ether}(Collateral(0.2 ether, 0 ether, 1.4 ether), 160); //increase loan
        assertEq(vaultClone.ethCollateral(), 1.2 ether);
        assertEq(weth.balanceOf(address(vaultClone)), 1 ether);
        assertEq(wbtc.balanceOf(address(vaultClone)), 2.4 ether);
        assertEq(vaultClone.collateralizationPercentage(), 160);
        assertEq(vaultClone.totalCollateralInDollars(), 42211149312288000000000);
        assertEq(vaultClone.debt(), 42211149312288000000000 * 10 / 16);

        vaultClone.payLoan();
        console.log(vaultClone.debt());
        console.log(vaultClone.totalCollateralInDollars());
        console.log(vaultClone.collateralizationPercentage());
        console.log(wbtc.balanceOf(address(vaultClone)));
    }
}
