// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IUSDe is IERC20, IERC20Permit, IERC20Metadata {
  function mint(address _to, uint256 _amount) external;

  function burn(uint256 _amount) external;

  function burnFrom(address account, uint256 amount) external;

  function grantRole(bytes32 role, address account) external;

  function setMinter(address newMinter) external;
}
