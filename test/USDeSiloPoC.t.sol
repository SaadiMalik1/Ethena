// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

/**
 * @title Simplified USDeSilo Vulnerability PoC
 * @notice Demonstrates the unchecked transfer vulnerability
 */

// ============================================================================
// INTERFACES
// ============================================================================

interface IUSDeSiloDefinitions {
    error OnlyStakingVault();
}

// ============================================================================
// PAUSABLE TOKEN (Returns false instead of reverting)
// ============================================================================

contract PausableToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public paused;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function pause() external {
        paused = true;
    }

    function unpause() external {
        paused = false;
    }

    // WARNING: Returns false instead of reverting when paused
    function transfer(address to, uint256 amount) external returns (bool) {
        if (paused) return false;
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (paused) return false;
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(balanceOf[from] >= amount, "Insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// ============================================================================
// VULNERABLE SILO
// ============================================================================

contract VulnerableUSDeSilo is IUSDeSiloDefinitions {
    address public immutable STAKING_VAULT;
    PausableToken public immutable TOKEN;

    constructor(address stakingVault, address token) {
        STAKING_VAULT = stakingVault;
        TOKEN = PausableToken(token);
    }

    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        // VULNERABLE: No return value check!
        TOKEN.transfer(to, amount);
    }
}

// ============================================================================
// INTEGRATED STAKING VAULT (Silo built-in for simplicity)
// ============================================================================

contract IntegratedVault {
    PausableToken public token;
    VulnerableUSDeSilo public silo;

    mapping(address => uint256) public userBalances;

    constructor(address _token) {
        token = PausableToken(_token);
        // Deploy silo with this vault as the authorized caller
        silo = new VulnerableUSDeSilo(address(this), _token);
    }

    function deposit(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(silo), amount), "Transfer failed");
        userBalances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        require(userBalances[msg.sender] >= amount, "Insufficient balance");

        // Update accounting BEFORE withdrawal
        userBalances[msg.sender] -= amount;

        // WARNING: If this doesn't revert, accounting is corrupted!
        silo.withdraw(msg.sender, amount);
    }

    function getSiloBalance() external view returns (uint256) {
        return token.balanceOf(address(silo));
    }
}

// ============================================================================
// PROOF OF CONCEPT TEST
// ============================================================================

contract USDeSiloVulnerabilityTest is Test {
    PausableToken public token;
    IntegratedVault public vault;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    function setUp() public {
        // Deploy token
        token = new PausableToken();

        // Deploy integrated vault (which deploys silo internally)
        vault = new IntegratedVault(address(token));

        // Give Alice and Bob tokens
        token.mint(alice, 100_000 ether);
        token.mint(bob, 100_000 ether);

        emit log("");
        emit log("=== SETUP COMPLETE ===");
        emit log_named_uint("Alice balance", token.balanceOf(alice) / 1 ether);
        emit log_named_uint("Bob balance", token.balanceOf(bob) / 1 ether);
    }

    function test_ExploitDemonstration() public {
        emit log("");
        emit log("=== EXPLOIT TEST ===");
        emit log("");

        // Step 1: Alice deposits
        emit log("Step 1: Alice deposits 10,000 tokens");
        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.deposit(10_000 ether);
        vm.stopPrank();

        emit log_named_uint("  Alice vault balance", vault.userBalances(alice) / 1 ether);
        emit log_named_uint("  Silo holds", vault.getSiloBalance() / 1 ether);
        emit log("");

        // Step 2: Token gets paused
        emit log("Step 2: Token gets PAUSED (simulating emergency)");
        token.pause();
        emit log_named_string("  Token paused", token.paused() ? "true" : "false");
        emit log("");

        // Step 3: Alice tries to withdraw while paused
        emit log("Step 3: Alice attempts withdrawal while paused");
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 aliceVaultBefore = vault.userBalances(alice);

        vm.prank(alice);
        vault.withdraw(10_000 ether); // This completes without reverting!

        uint256 aliceBalanceAfter = token.balanceOf(alice);
        uint256 aliceVaultAfter = vault.userBalances(alice);

        emit log("");
        emit log("=== !!! EXPLOIT SUCCESSFUL !!! ===");
        emit log_named_uint("Alice token balance BEFORE", aliceBalanceBefore / 1 ether);
        emit log_named_uint("Alice token balance AFTER ", aliceBalanceAfter / 1 ether);
        emit log_named_uint("Alice vault balance BEFORE", aliceVaultBefore / 1 ether);
        emit log_named_uint("Alice vault balance AFTER ", aliceVaultAfter / 1 ether);
        emit log("");
        emit log(">>> CRITICAL: Vault thinks Alice withdrew everything");
        emit log(">>> CRITICAL: Alice actually received ZERO tokens");
        emit log_named_uint(">>> CRITICAL: Tokens stuck in silo", vault.getSiloBalance() / 1 ether);
        emit log(">>> CRITICAL: Alice CANNOT withdraw again");
        emit log("");

        // Verify the exploit worked
        assertEq(aliceBalanceBefore, aliceBalanceAfter, "Alice should not have received tokens");
        assertEq(aliceVaultAfter, 0, "Vault should show 0 balance for Alice");
        assertEq(vault.getSiloBalance(), 10_000 ether, "Tokens should be stuck in silo");

        emit log("=== FINAL STATE ===");
        emit log("Alice permanently lost: 10,000 tokens");
        emit log_named_uint("Tokens stuck forever in silo", vault.getSiloBalance() / 1 ether);
        emit log("Recovery: IMPOSSIBLE");
        emit log("");
    }

    function test_NormalOperation() public {
        emit log("");
        emit log("=== NORMAL OPERATION TEST ===");
        emit log("");

        // Deposit
        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.deposit(10_000 ether);
        emit log("Alice deposited 10,000 tokens");

        // Withdraw (works fine when not paused)
        vault.withdraw(10_000 ether);
        emit log("Alice withdrew 10,000 tokens");
        vm.stopPrank();

        emit log_named_uint("Alice final balance", token.balanceOf(alice) / 1 ether);
        emit log("SUCCESS: Normal operation works correctly");
        emit log("");

        assertEq(token.balanceOf(alice), 100_000 ether, "Alice should have all tokens back");
    }

    function test_MultipleUsersImpact() public {
        emit log("");
        emit log("=== MULTIPLE USERS IMPACT TEST ===");
        emit log("");

        // Both Alice and Bob deposit
        emit log("Step 1: Alice and Bob deposit tokens");
        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.deposit(10_000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(vault), 5_000 ether);
        vault.deposit(5_000 ether);
        vm.stopPrank();

        emit log("  Alice deposited: 10,000");
        emit log("  Bob deposited: 5,000");
        emit log_named_uint("  Total in silo", vault.getSiloBalance() / 1 ether);
        emit log("");

        // Pause token
        emit log("Step 2: Token gets PAUSED");
        token.pause();
        emit log("");

        // Alice withdraws during pause (loses funds)
        emit log("Step 3: Alice withdraws during pause");
        vm.prank(alice);
        vault.withdraw(10_000 ether);
        emit log_named_uint("  Alice vault balance", vault.userBalances(alice) / 1 ether);
        emit log_named_uint("  Alice token balance", token.balanceOf(alice) / 1 ether);
        emit log("  >>> Alice LOST 10,000 tokens!");
        emit log("");

        // Unpause
        emit log("Step 4: Token gets unpaused");
        token.unpause();
        emit log("");

        // Bob can now withdraw successfully
        emit log("Step 5: Bob withdraws after unpause");
        vm.prank(bob);
        vault.withdraw(5_000 ether);
        emit log_named_uint("  Bob vault balance", vault.userBalances(bob) / 1 ether);
        emit log_named_uint("  Bob token balance", token.balanceOf(bob) / 1 ether);
        emit log("  >>> Bob successfully received 5,000 tokens");
        emit log("");

        emit log("=== FINAL COMPARISON ===");
        emit log("Alice: LOST 10,000 tokens (PERMANENT)");
        emit log("Bob  : SAFE, withdrew 5,000 tokens");
        emit log_named_uint("Still stuck in silo", vault.getSiloBalance() / 1 ether);
        emit log("");

        // Verify
        assertEq(token.balanceOf(alice), 90_000 ether, "Alice lost 10k");
        assertEq(token.balanceOf(bob), 100_000 ether, "Bob got everything back");
        assertEq(vault.getSiloBalance(), 10_000 ether, "10k stuck forever");
    }
}
