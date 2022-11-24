// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "solmate/tokens/ERC20.sol";
import "openzeppelin/utils/Strings.sol";

error Unauthorized();

contract StableCoin is ERC20 {
    mapping(address => uint256) public vaults;
    address public vaultFactory;

    constructor(string memory _name, string memory _symbol, address _vaultFactory) ERC20(_name, _symbol, 18) {
        vaultFactory = _vaultFactory;
    }

    function mint(address recipient, uint256 amount) external {
        if (vaults[msg.sender] != 1) revert Unauthorized();
        _mint(recipient, amount);
    }

    function burn(address recipient, uint256 amount) external {
        if (vaults[msg.sender] != 1) revert Unauthorized();
        _burn(recipient, amount);
    }

    function addVault(address vault) external {
        if (msg.sender != vaultFactory) revert Unauthorized();
        vaults[vault] = 1;
    }
}
