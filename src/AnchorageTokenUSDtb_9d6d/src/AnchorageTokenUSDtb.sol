// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ReentrancyGuardUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable-v4/contracts/security/ReentrancyGuardUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable-v4/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable-v4/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable-v4/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20Upgradeable} from "../lib/openzeppelin-contracts-upgradeable-v4/contracts/token/ERC20/ERC20Upgradeable.sol";

import {SingleAdminAccessControlUpgradeable} from "./SingleAdminAccessControlUpgradeable.sol";

/**
 * @dev STORAGE Mirrors USDtb's legacy storage.
 * DO NOT reorder/remove. Only append after this block.
 */
abstract contract USDtbStorage {
    // solhint-disable private-vars-leading-underscore
    /**
     * @dev DEPRECATED: Legacy minter contract role, no longer used.
     */
    bytes32 public constant __DEPRECATED_MINTER_CONTRACT = keccak256("MINTER_CONTRACT");

    /**
     * @dev DEPRECATED: Legacy blacklist manager role, no longer used.
     */
    bytes32 public constant __DEPRECATED_BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    /**
     * @dev DEPRECATED: Legacy whitelist manager role, no longer used.
     */
    bytes32 public constant __DEPRECATED_WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    /**
     * @dev Role assigned to blocked accounts that are restricted from transferring tokens
     */
    bytes32 public constant BLACKLISTED_ROLE = keccak256("BLACKLISTED_ROLE");

    /**
     * @dev DEPRECATED: Legacy whitelisted role, no longer used.
     */
    bytes32 public constant __DEPRECATED_WHITELISTED_ROLE = keccak256("WHITELISTED_ROLE");

    /**
     * @notice Thrown when a caller lacks permission for a restricted operation
     */
    error OperationNotAllowed();

    /**
     * @notice DEPRECATED: This enum is no longer used.
     * @dev Legacy transfer state control.
     */
    enum TransferState {
        FULLY_DISABLED,
        WHITELIST_ENABLED,
        FULLY_ENABLED
    }

    /**
     * @notice DEPRECATED: Transfer state, occupies original slot.
     */
    TransferState internal _transferState;
}

/**
 * @title AnchorageTokenUSDtb
 * @dev TransparentProxy-upgradeable ERC20 token for regulated stablecoin issuance.
 * Implements access control, minting/burning, pausing, account blocking, and permit support.
 * @custom:security-contact security@anchorage.com
 */
contract AnchorageTokenUSDtb is
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    ReentrancyGuardUpgradeable,
    SingleAdminAccessControlUpgradeable,
    USDtbStorage,
    ERC20PausableUpgradeable
{
    /**
     * @dev Custom error thrown when attempting to interact with a blocked account
     */
    error AccountBlocked();

    /**
     * @dev Error thrown when a deprecated function is called.
     * @notice This error indicates an attempt to use functionality that has been removed.
     */
    error Deprecated();

    /**
     * @dev Error thrown when a zero address is provided where a valid address is required
     */
    error ZeroAddress();

    /**
     * @dev Role identifier for accounts that can mint and burn tokens
     */
    bytes32 public constant MINTER_BURNER_ROLE = keccak256("MINTER_BURNER_ROLE");

    /**
     * @dev Role identifier for accounts that can block and unblock other accounts
     */
    bytes32 public constant BLOCKLISTER_ROLE = keccak256("BLOCKLISTER_ROLE");

    /**
     * @dev Role identifier for accounts that can pause and unpause the contract
     */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Emitted when accounts are blocked
     */
    event AccountsBlocked(address[] accounts);

    /**
     * @dev Emitted when accounts are unblocked
     */
    event AccountsUnblocked(address[] accounts);

    /**
     * @dev Constructor that disables initializers to prevent implementation contract initialization
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with name, symbol, and admin address
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param admin The address that will receive the admin role and all other roles
     * @notice This function can only be called once during proxy deployment
     */
    function initialize(string memory name, string memory symbol, address admin) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @dev Initializes V2 of the contract with role assignments
     * @param admin The address that will receive the admin role (replaces current admin)
     * @param minterBurner The address that will receive the minter/burner role
     * @param blocklister The address that will receive the blocklister role
     * @param pauser The address that will receive the pauser role
     * @notice This function can only be called once during upgrade to V2
     * @notice The admin role will be transferred from the current admin to the new admin
     */
    function initializeV2(address admin, address minterBurner, address blocklister, address pauser)
        public
        reinitializer(2)
    {
        if (admin == address(0)) revert ZeroAddress();
        if (minterBurner == address(0)) revert ZeroAddress();
        if (blocklister == address(0)) revert ZeroAddress();
        if (pauser == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_BURNER_ROLE, minterBurner);
        _grantRole(BLOCKLISTER_ROLE, blocklister);
        _grantRole(PAUSER_ROLE, pauser);
    }

    /**
     * @dev Mints new tokens to the specified address
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     * @notice Only accounts with MINTER_BURNER_ROLE can call this function
     * @notice Cannot mint to blocked accounts
     * @notice Cannot mint when contract is paused
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_BURNER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the specified address
     * @param from The address whose tokens will be burned
     * @param amount The amount of tokens to burn
     * @notice Only accounts with MINTER_BURNER_ROLE can call this function
     * @notice Can burn from blocked accounts
     * @notice Cannot burn when contract is paused
     */
    function burn(address from, uint256 amount) public onlyRole(MINTER_BURNER_ROLE) whenNotPaused {
        _burn(from, amount);
    }

    /**
     * @dev Blocks multiple accounts from transferring or receiving tokens
     * @param accounts Array of addresses to block
     * @notice Only accounts with BLOCKLISTER_ROLE can call this function
     */
    function blockAccounts(address[] calldata accounts) public onlyRole(BLOCKLISTER_ROLE) {
        uint256 length = accounts.length;
        for (uint256 i; i < length;) {
            _grantRole(BLACKLISTED_ROLE, accounts[i]);
            unchecked {
                ++i;
            }
        }
        emit AccountsBlocked(accounts);
    }

    /**
     * @dev Unblocks multiple accounts, allowing them to transfer and receive tokens
     * @param accounts Array of addresses to unblock
     * @notice Only accounts with BLOCKLISTER_ROLE can call this function
     */
    function unblockAccounts(address[] calldata accounts) public onlyRole(BLOCKLISTER_ROLE) {
        uint256 length = accounts.length;
        for (uint256 i; i < length;) {
            _revokeRole(BLACKLISTED_ROLE, accounts[i]);
            unchecked {
                ++i;
            }
        }
        emit AccountsUnblocked(accounts);
    }

    /**
     * @dev Pauses all token transfers, minting, and burning
     * @notice Only accounts with PAUSER_ROLE can call this function
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers, minting, and burning
     * @notice Only accounts with PAUSER_ROLE can call this function
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Checks if an account is blocked
     * @param account The address to check
     * @return bool True if the account is blocked, false otherwise
     */
    function isBlocked(address account) public view returns (bool) {
        return hasRole(BLACKLISTED_ROLE, account);
    }

    function renounceRole(bytes32 role, address account) public override {
        if (role == BLACKLISTED_ROLE) revert OperationNotAllowed();
        super.renounceRole(role, account);
    }

    /**
     * @dev Internal function that handles token transfers before the transfer
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param value The amount of tokens to transfer
     * @notice Reverts if either the sender or receiver is blocked (except for burning)
     * @notice Prevents minting to blocked addresses
     */
    function _beforeTokenTransfer(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        // Allow burning (to == address(0)) but prevent minting (from == address(0)) to blocked addresses
        // Block regular transfers involving blocked accounts
        if (to != address(0) && (isBlocked(from) || isBlocked(to))) revert AccountBlocked();

        super._beforeTokenTransfer(from, to, value);
    }

    /**
     * @dev Deprecated burn function that reverts when called
     * @notice This function exists only to explicitly mark the legacy burn interface as deprecated
     * @custom:deprecated This function is deprecated and will always revert
     */
    function burn(uint256) public pure override(ERC20BurnableUpgradeable) {
        revert Deprecated();
    }

    /**
     * @dev Deprecated burnFrom function that reverts when called
     * @notice This function exists only to explicitly mark the legacy burnFrom interface as deprecated
     * @custom:deprecated This function is deprecated and will always revert
     */
    function burnFrom(address, uint256) public pure override(ERC20BurnableUpgradeable) {
        revert Deprecated();
    }
}
