// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { USDeOFTAdapter } from "../usde/USDeOFTAdapter.sol";

/**
 * @title StakedUSDeOFTAdapter
 */
contract StakedUSDeOFTAdapter is USDeOFTAdapter {
    // @dev The role which prevents an address to transfer, stake, or unstake.
    // The owner of the contract can redirect address staking balance if an address is in full restricting mode.
    bytes32 private constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");

    event RedistributeFunds(address indexed user, uint256 amount);

    /**
     * @dev Constructor to initialize the StakedUSDeOFTAdapter contract.
     * @param _rateLimitConfigs An array of RateLimitConfig structures defining the rate limits.
     * @param _token Address of the token contract.
     * @param _lzEndpoint Address of the LZ endpoint.
     * @param _delegate Address of the delegate.
     */
    constructor(
        RateLimitConfig[] memory _rateLimitConfigs,
        address _token,
        address _lzEndpoint,
        address _delegate
    ) USDeOFTAdapter(_rateLimitConfigs, _token, _lzEndpoint, _delegate) {}

    /**
     * @dev Credits tokens to the recipient while checking if the recipient is blacklisted.
     * If blacklisted, redistributes the funds to the contract owner.
     * @param _to The address of the recipient.
     * @param _amountLD The amount of tokens to credit.
     * @param _srcEid The source endpoint identifier.
     * @return amountReceivedLD The actual amount of tokens received.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        // @dev query the underlying token to check if "to" address is blacklisted
        (bool success, bytes memory data) = address(innerToken).call(
            abi.encodeWithSignature("hasRole(bytes32,address)", FULL_RESTRICTED_STAKER_ROLE, _to)
        );
        bool isBlackListed = abi.decode(data, (bool));

        // If the call fails, OR recipient is blacklisted, emit an event, redistribute funds, and credit the owner
        if (!success || isBlackListed) {
            emit RedistributeFunds(_to, _amountLD);
            return super._credit(owner(), _amountLD, _srcEid);
        } else {
            return super._credit(_to, _amountLD, _srcEid);
        }
    }
}
