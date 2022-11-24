// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "src/interface/IVault.sol";
import "src/Vault.sol";
import "test/utils/Vault.utils.sol";
import {VaultFactory} from "src/VaultFactory.sol";
import {StableCoin} from "src/Stablecoin.sol";
import {MockERC20} from "test/mock/MockERC20.sol";

contract VaultIntegrationTest is Test {
    address public deployer;
    address public user;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address wbtcAggregator = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address wethAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address ethAggregator = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    MockERC20 weth;
    MockERC20 wbtc;
    uint256 mainnetFork;
    Vault vault;
    VaultUtils utils = new VaultUtils();
    IVault vaultClone;
    StableCoin stablecoin;
    VaultFactory factory;

    function setUp() public {
        deployer = vm.addr(1);
        user = vm.addr(1);

        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        vm.prank(deployer);
        weth = new MockERC20("weth", "weth");
        wbtc = new MockERC20("wbtc", "wbtc");
        vault = new Vault();
        factory =
        new VaultFactory(3, address(vault), address(weth), address(wbtc), wbtcAggregator, wethAggregator, ethAggregator);
        stablecoin = StableCoin(factory.stablecoin());

        vm.startPrank(user);
        vaultClone = IVault(factory.createVault());
        vm.deal(user, 100 ether);
        weth.mint(100 ether);
        wbtc.mint(100 ether);
        ERC20(weth).approve(address(vaultClone), type(uint256).max);
        ERC20(wbtc).approve(address(vaultClone), type(uint256).max);
    }

    function testTakeLoan() public {
        vaultClone.takeLoan{value: 1 ether}(Collateral(1 ether, 1 ether, 1 ether), 200);
        assertEq(vaultClone.ethCollateral(), 1 ether);
        assertEq(weth.balanceOf(address(vaultClone)), 1 ether);
        assertEq(wbtc.balanceOf(address(vaultClone)), 1 ether);
    }

    function testInitializer() public {
        vm.expectRevert(AlreadyInitialized.selector);
        vault.initialize(address(this));
    }
}
