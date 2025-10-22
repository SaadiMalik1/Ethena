// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTOwnable2StepAdapter } from "../libs/OFTOwnable2StepAdapter.sol";
import { RateLimiter } from "../libs/RateLimiter.sol";

/**
 * @title USDeOFTAdapter
 */
contract USDeOFTAdapter is OFTOwnable2StepAdapter, RateLimiter {
    // Address of the rate limiter
    address public rateLimiter;

    // Event emitted when the rate limiter is set
    event RateLimiterSet(address indexed rateLimiter);

    // Error to be thrown when only the rate limiter is allowed to perform an action
    error OnlyRateLimiter();

    /**
     * @dev Constructor to initialize the USDeOFTAdapter contract.
     * @param _rateLimitConfigs An array of RateLimitConfig structures defining the rate limits.
     * @param _token Address of the token contract.
     * @param _lzEndpoint Address of the LZ endpoint.
     * @param _delegate Address of the OApp delegate.
     */
    constructor(
        RateLimitConfig[] memory _rateLimitConfigs,
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTOwnable2StepAdapter(_token, _lzEndpoint, _delegate) {
        _setRateLimits(_rateLimitConfigs);
    }

    /**
     * @dev Sets the rate limiter contract address. Only callable by the owner.
     * @param _rateLimiter Address of the rate limiter contract.
     */
    function setRateLimiter(address _rateLimiter) external onlyOwner {
        rateLimiter = _rateLimiter;
        emit RateLimiterSet(_rateLimiter);
    }

    /**
     * @dev Sets the rate limits based on RateLimitConfig array. Only callable by the owner or the rate limiter.
     * @param _rateLimitConfigs An array of RateLimitConfig structures defining the rate limits.
     */
    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external {
        if (msg.sender != rateLimiter && msg.sender != owner()) revert OnlyRateLimiter();
        _setRateLimits(_rateLimitConfigs);
    }

    /**
     * @dev Checks and updates the rate limit before initiating a token transfer.
     * @param _amountLD The amount of tokens to be transferred.
     * @param _minAmountLD The minimum amount of tokens expected to be received.
     * @param _dstEid The destination endpoint identifier.
     * @return amountSentLD The actual amount of tokens sent.
     * @return amountReceivedLD The actual amount of tokens received.
     */
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _checkAndUpdateRateLimit(_dstEid, _amountLD);
        return super._debit(_amountLD, _minAmountLD, _dstEid);
    }
}
