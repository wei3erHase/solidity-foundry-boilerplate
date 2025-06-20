// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {WrappedHAI} from "../src/WrappedHAI.sol";
import {IOracleRelayer} from "../src/IOracleRelayer.sol";
import {MockHAI} from "./mocks/MockHAI.sol";
import {MockOracleRelayer} from "./mocks/MockOracleRelayer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WrappedHAITest is Test {
    WrappedHAI internal wHAI;
    MockHAI internal hai;
    MockOracleRelayer internal oracle;

    address internal deployer;
    address internal alice = vm.addr(0x1);
    address internal bob = vm.addr(0x2);

    uint256 internal constant INITIAL_PRICE = 2 * 1e18;
    uint256 internal constant PRECISION_FACTOR = 1e18;
    uint256 internal aliceInitialBalance = 1_000_000 * 1e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed user, uint256 haiAmount, uint256 whaiAmount);

    function setUp() public {
        deployer = address(this);
        hai = new MockHAI();
        oracle = new MockOracleRelayer(INITIAL_PRICE);
        wHAI = new WrappedHAI(address(hai), address(oracle));

        hai.transfer(alice, aliceInitialBalance);
        vm.label(deployer, "Deployer");
        vm.label(address(hai), "MockHAI_Token");
        vm.label(address(oracle), "MockOracle");
        vm.label(address(wHAI), "WrappedHAI_Contract");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
    }

    function test_InitialState() public {
        assertEq(wHAI.name(), "Wrapped HAI", "InitialState: Name mismatch");
        assertEq(wHAI.symbol(), "wHAI", "InitialState: Symbol mismatch");
        assertEq(wHAI.decimals(), 18, "InitialState: Decimals mismatch");
        assertEq(address(wHAI.HAI()), address(hai), "InitialState: HAI address mismatch");
        assertEq(address(wHAI.ORACLE_RELAYER()), address(oracle), "InitialState: Oracle mismatch");
        assertEq(wHAI.totalSupply(), 0, "InitialState: wHAI total supply non-zero");
        assertEq(hai.balanceOf(address(wHAI)), 0, "InitialState: Contract HAI balance non-zero");
        assertEq(wHAI.balanceOf(alice), 0, "InitialState: Alice wHAI balance non-zero");
        assertEq(wHAI.owner(), deployer, "InitialState: Owner mismatch");
        assertSolvency();
    }

    function test_Deposit_Successful_ToBob() public {
        uint256 depositHaiAmount = 100 * 1e18;

        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);

        vm.expectEmit(true, true, true, true, address(wHAI));
        emit Deposit(bob, depositHaiAmount, (depositHaiAmount * INITIAL_PRICE) / PRECISION_FACTOR);

        vm.expectEmit(true, true, true, true, address(wHAI));
        emit Transfer(address(0), bob, (depositHaiAmount * INITIAL_PRICE) / PRECISION_FACTOR);

        uint256 mintedWhaiAmount = wHAI.deposit(depositHaiAmount, bob);
        vm.stopPrank();

        assertEq(hai.balanceOf(alice), aliceInitialBalance - depositHaiAmount, "Deposit: Alice HAI balance incorrect");
        assertEq(hai.balanceOf(address(wHAI)), depositHaiAmount, "Deposit: Contract HAI balance incorrect");

        uint256 expectedWhaiBob = (depositHaiAmount * INITIAL_PRICE) / PRECISION_FACTOR;
        assertEq(wHAI.balanceOf(bob), expectedWhaiBob, "Deposit: Bob wHAI balance incorrect");
        assertEq(mintedWhaiAmount, expectedWhaiBob, "Deposit: Minted wHAI amount incorrect");
        assertEq(wHAI.totalSupply(), expectedWhaiBob, "Deposit: Total wHAI supply incorrect");

        assertSolvency();
    }

    function test_Deposit_PriceChange_BalanceUpdate() public {
        uint256 depositHaiAmount = 100 * 1e18;
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice);
        vm.stopPrank();

        uint256 expectedWhaiInitial = (depositHaiAmount * INITIAL_PRICE) / PRECISION_FACTOR;
        assertEq(wHAI.balanceOf(alice), expectedWhaiInitial, "PriceChange: Initial wHAI balance incorrect");
        assertSolvency();

        uint256 newPrice = 3 * 1e18;
        vm.prank(deployer);
        oracle.setRedemptionPrice(newPrice);

        uint256 expectedWhaiAfterPriceChange = (depositHaiAmount * newPrice) / PRECISION_FACTOR;
        assertEq(wHAI.balanceOf(alice), expectedWhaiAfterPriceChange, "PriceChange: wHAI balance after price up incorrect");
        assertEq(wHAI.totalSupply(), expectedWhaiAfterPriceChange, "PriceChange: TotalSupply after price up incorrect");
        assertSolvency();

        vm.prank(deployer);
        oracle.setRedemptionPrice(0);
        assertEq(wHAI.balanceOf(alice), 0, "PriceChange: wHAI balance after price zero incorrect");
        assertEq(wHAI.totalSupply(), 0, "PriceChange: TotalSupply after price zero incorrect");
        assertSolvency();
    }

    function assertSolvency() internal {
        uint256 wTotalSupply_ = wHAI.totalSupply();
        uint256 contractHaiBalance_ = hai.balanceOf(address(wHAI));
        uint256 price_ = oracle.redemptionPrice();

        if (price_ == 0) {
            assertTrue(wTotalSupply_ == 0, "Solvency: wTotalSupply must be 0 if price is 0");
        } else {
            assertEq(wTotalSupply_, (contractHaiBalance_ * price_) / PRECISION_FACTOR, "Solvency: Invariant broken");
        }
    }

    // --- Transfer Tests ---
    function test_Transfer_Successful() public {
        uint256 depositHaiAmount = 200 * 1e18;
        // Calculate wHAI amount based on deposit and initial price to avoid issues if INITIAL_PRICE changes
        // This represents 50 HAI worth of wHAI
        uint256 transferWhaiAmount = (50 * 1e18 * INITIAL_PRICE) / PRECISION_FACTOR;

        // Alice deposits HAI for herself
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice);
        vm.stopPrank();

        uint256 aliceInitialWhaiBalance = wHAI.balanceOf(alice);
        uint256 bobInitialWhaiBalance = wHAI.balanceOf(bob);

        // Alice transfers wHAI to Bob
        vm.startPrank(alice);
        // Expect Transfer event from wHAI contract
        vm.expectEmit(true, true, true, true, address(wHAI));
        emit Transfer(alice, bob, transferWhaiAmount);
        bool success = wHAI.transfer(bob, transferWhaiAmount);
        assertTrue(success, "Transfer failed unexpectedly");
        vm.stopPrank();

        // Check wHAI balances
        assertEq(wHAI.balanceOf(alice), aliceInitialWhaiBalance - transferWhaiAmount, "Transfer: Alice wHAI balance incorrect");
        assertEq(wHAI.balanceOf(bob), bobInitialWhaiBalance + transferWhaiAmount, "Transfer: Bob wHAI balance incorrect");

        // Verify underlying HAI changes by calculating what their HAI balance should be
        // This is an indirect check of _balances array.
        // A direct check of _balances is not possible as it's private.
        // We can verify by simulating a full withdrawal or by checking total supply and other balances.
        // For now, solvency check covers overall integrity.

        assertSolvency();
    }

    function test_Transfer_Reverts_InsufficientBalance() public {
        uint256 depositHaiAmount = 50 * 1e18; // Alice deposits 50 HAI

        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice);
        uint256 aliceWhaiBalance = wHAI.balanceOf(alice); // Get current wHAI balance

        vm.expectRevert("WrappedHAI: Transfer amount exceeds underlying HAI balance for sender");
        wHAI.transfer(bob, aliceWhaiBalance + 1); // Try to transfer more wHAI than she has
        vm.stopPrank();
        assertSolvency();
    }

    function test_Transfer_Reverts_WhenPriceIsZero() public {
        uint256 depositHaiAmount = 100 * 1e18;
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice); // Alice has some wHAI
        vm.stopPrank();

        vm.prank(deployer);
        oracle.setRedemptionPrice(0); // Price goes to zero

        vm.startPrank(alice);
        vm.expectRevert("WrappedHAI: Redemption price is zero, cannot transfer wHAI");
        wHAI.transfer(bob, 10 * 1e18); // Attempt to transfer non-zero wHAI
        vm.stopPrank();
        assertSolvency(); // wTotalSupply should be 0
    }

    function test_Transfer_ZeroWhaiAmount() public {
        uint256 depositHaiAmount = 100 * 1e18;
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice);
        vm.stopPrank();

        uint256 aliceWhaiBalanceBefore = wHAI.balanceOf(alice);
        uint256 bobWhaiBalanceBefore = wHAI.balanceOf(bob);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true, address(wHAI));
        emit Transfer(alice, bob, 0);
        assertTrue(wHAI.transfer(bob, 0), "Transfer of 0 wHAI failed");
        vm.stopPrank();

        assertEq(wHAI.balanceOf(alice), aliceWhaiBalanceBefore, "TransferZero: Alice balance changed");
        assertEq(wHAI.balanceOf(bob), bobWhaiBalanceBefore, "TransferZero: Bob balance changed");
        assertSolvency();
    }

    // --- TransferFrom Tests ---
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function test_TransferFrom_Successful() public {
        uint256 depositHaiAmount = 200 * 1e18;
        // Approve 100 HAI worth of wHAI
        uint256 approveWhaiAmount = (100 * 1e18 * INITIAL_PRICE) / PRECISION_FACTOR;
        // Transfer 50 HAI worth of wHAI
        uint256 transferWhaiAmount = (50 * 1e18 * INITIAL_PRICE) / PRECISION_FACTOR;

        // Alice deposits HAI for herself
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice);

        // Alice approves Bob to spend her wHAI
        vm.expectEmit(true, true, true, true, address(wHAI));
        emit Approval(alice, bob, approveWhaiAmount);
        wHAI.approve(bob, approveWhaiAmount);
        vm.stopPrank();

        assertEq(wHAI.allowance(alice, bob), approveWhaiAmount, "TransferFrom: Allowance incorrect before transfer");
        uint256 aliceWhaiBalanceBefore = wHAI.balanceOf(alice);
        uint256 bobWhaiBalanceBefore = wHAI.balanceOf(bob);

        // Bob transfers wHAI from Alice to himself
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true, address(wHAI)); // Approval event for reduced allowance
        emit Approval(alice, bob, approveWhaiAmount - transferWhaiAmount);
        vm.expectEmit(true, true, true, true, address(wHAI)); // Transfer event
        emit Transfer(alice, bob, transferWhaiAmount);

        assertTrue(wHAI.transferFrom(alice, bob, transferWhaiAmount), "transferFrom failed");
        vm.stopPrank();

        assertEq(wHAI.allowance(alice, bob), approveWhaiAmount - transferWhaiAmount, "TransferFrom: Allowance incorrect after transfer");
        assertEq(wHAI.balanceOf(alice), aliceWhaiBalanceBefore - transferWhaiAmount, "TransferFrom: Alice wHAI balance incorrect");
        assertEq(wHAI.balanceOf(bob), bobWhaiBalanceBefore + transferWhaiAmount, "TransferFrom: Bob wHAI balance incorrect");
        assertSolvency();
    }

    function test_TransferFrom_Reverts_InsufficientAllowance() public {
        uint256 depositHaiAmount = 100 * 1e18;
        uint256 approveWhaiAmount = (10 * 1e18 * INITIAL_PRICE) / PRECISION_FACTOR;
        uint256 transferWhaiAmount = (20 * 1e18 * INITIAL_PRICE) / PRECISION_FACTOR; // More than allowance

        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice);
        wHAI.approve(bob, approveWhaiAmount); // Alice approves Bob for 10 wHAI (value)
        vm.stopPrank();

        vm.startPrank(bob);
        // For OpenZeppelin ERC20, the actual error is ERC20InsufficientAllowance(spender, balance, needed)
        // spender is bob, balance is approveWhaiAmount, needed is transferWhaiAmount
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, bob, approveWhaiAmount, transferWhaiAmount));
        wHAI.transferFrom(alice, bob, transferWhaiAmount);
        vm.stopPrank();
        assertSolvency();
    }


    // --- Withdraw Tests ---
    event Withdraw(address indexed owner, address indexed receiver, uint256 haiAmount, uint256 whaiAmount);

    function test_Withdraw_Successful_OwnerSelf() public {
        uint256 depositHaiAmount = 100 * 1e18;
        uint256 withdrawHaiAmount = 30 * 1e18;

        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice); // Alice deposits 100 HAI for herself
        vm.stopPrank();

        uint256 initialContractHaiBalance = hai.balanceOf(address(wHAI));
        uint256 aliceHaiBalanceBeforeWithdraw = hai.balanceOf(alice);
        uint256 whaiTotalSupplyBefore = wHAI.totalSupply();
        uint256 aliceWhaiBalanceBefore = wHAI.balanceOf(alice);
        uint256 expectedWhaiBurned = (withdrawHaiAmount * INITIAL_PRICE) / PRECISION_FACTOR;

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true, address(wHAI));
        emit Withdraw(alice, alice, withdrawHaiAmount, expectedWhaiBurned);
        vm.expectEmit(true, true, true, true, address(wHAI));
        emit Transfer(alice, address(0), expectedWhaiBurned);

        uint256 whaiBurned = wHAI.withdraw(withdrawHaiAmount, alice, alice);
        vm.stopPrank();

        assertEq(whaiBurned, expectedWhaiBurned, "Withdraw: Incorrect wHAI burned amount returned");
        assertEq(hai.balanceOf(address(wHAI)), initialContractHaiBalance - withdrawHaiAmount, "Withdraw: Contract HAI balance incorrect");
        assertEq(hai.balanceOf(alice), aliceHaiBalanceBeforeWithdraw + withdrawHaiAmount, "Withdraw: Alice HAI balance after withdraw incorrect");
        assertEq(wHAI.balanceOf(alice), aliceWhaiBalanceBefore - expectedWhaiBurned, "Withdraw: Alice wHAI balance after withdraw incorrect");
        assertEq(wHAI.totalSupply(), whaiTotalSupplyBefore - expectedWhaiBurned, "Withdraw: Total wHAI supply incorrect");
        assertSolvency();
    }

    function test_Withdraw_Reverts_InsufficientOwnerHai() public {
        uint256 depositHaiAmount = 50 * 1e18;
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice); // Alice deposits 50 HAI
        vm.stopPrank();

        uint256 withdrawHaiAmount = 60 * 1e18; // Try to withdraw more HAI than she has internally

        vm.startPrank(alice);
        vm.expectRevert("WrappedHAI: Owner has insufficient underlying HAI balance");
        wHAI.withdraw(withdrawHaiAmount, alice, alice);
        vm.stopPrank();
        assertSolvency();
    }

    function test_Withdraw_Reverts_WhenPriceIsZero() public {
        uint256 depositHaiAmount = 100 * 1e18;
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice);
        vm.stopPrank();

        vm.prank(deployer);
        oracle.setRedemptionPrice(0); // Price goes to zero

        vm.startPrank(alice);
        vm.expectRevert("WrappedHAI: Redemption price is zero, cannot withdraw HAI");
        wHAI.withdraw(10 * 1e18, alice, alice); // Attempt to withdraw HAI
        vm.stopPrank();
        assertSolvency(); // wTotalSupply should be 0
    }

    function test_Withdraw_Reverts_WhaiAmountCalculatesToZero() public {
        uint256 depositHaiAmount = 100 * 1e18; // Alice deposits 100 HAI
        vm.startPrank(alice);
        hai.approve(address(wHAI), depositHaiAmount);
        wHAI.deposit(depositHaiAmount, alice); // Alice's internal balance is 100 HAI
        vm.stopPrank();

        // Set redemptionPrice such that (tinyHaiAmount * redemptionPrice) / PRECISION_FACTOR results in 0 wHAI.
        // redemptionPrice = 1 wei. PRECISION_FACTOR = 1e18.
        // If tinyHaiAmount = 1e17 (0.1 HAI), then wHAI = (1e17 * 1) / 1e18 = 0.1 / 1 = 0 (due to integer truncation).
        vm.prank(deployer);
        oracle.setRedemptionPrice(1);

        uint256 tinyHaiAmountToWithdraw = 1e17; // 0.1 HAI

        vm.startPrank(alice);
        vm.expectRevert("WrappedHAI: wHAI amount is zero for non-zero HAI withdrawal; check precision or price");
        wHAI.withdraw(tinyHaiAmountToWithdraw, alice, alice);
        vm.stopPrank();
        assertSolvency();
    }

    // --- Fuzz Tests ---

    // Fuzz test for the deposit function
    // We'll fuzz the amount and the receiver.
    // Alice will be the depositor of HAI.
    function testFuzz_Deposit_Solvency(uint256 depositHaiAmount, address receiver) public {
        // Constrain fuzzed inputs to valid/interesting ranges
        vm.assume(depositHaiAmount > 0 && depositHaiAmount <= aliceInitialBalance / 2); // Avoid exhausting Alice's HAI quickly
        vm.assume(receiver != address(0) && receiver != address(this) && receiver != address(wHAI) && receiver != address(hai) && receiver != alice && receiver != bob && receiver != deployer);


        // Ensure oracle price is something reasonable for the fuzz run, not zero initially.
        vm.prank(deployer);
        uint256 currentPrice = oracle.redemptionPrice();
        if (currentPrice == 0) {
             oracle.setRedemptionPrice(INITIAL_PRICE); // Reset to a known non-zero price
        }
        currentPrice = oracle.redemptionPrice(); // update currentPrice after potential change


        uint256 aliceHaiBefore = hai.balanceOf(alice);
        uint256 contractHaiBefore = hai.balanceOf(address(wHAI));
        uint256 receiverWhaiBefore = wHAI.balanceOf(receiver);
        uint256 totalSupplyBefore = wHAI.totalSupply();

        vm.startPrank(alice);
        // It's possible Alice doesn't have enough HAI if depositHaiAmount is too large vs aliceInitialBalance
        // The vm.assume should handle this, but double check available balance for approval
        uint256 amountToApprove = depositHaiAmount > aliceHaiBefore ? aliceHaiBefore : depositHaiAmount;
        if (amountToApprove == 0 && depositHaiAmount > 0) { // if alice has no HAI but amount > 0, this test path is invalid
            vm.stopPrank();
            return;
        }
        hai.approve(address(wHAI), amountToApprove);

        // Perform the deposit
        // If amountToApprove is less than depositHaiAmount due to Alice running out, this will likely revert.
        // This is fine, fuzzing should catch reverts too. Or we only proceed if aliceHaiBefore >= depositHaiAmount.
        // The vm.assume already ensures depositHaiAmount <= aliceInitialBalance / 2,
        // and aliceInitialBalance is what Alice starts with.
        // So, this should be fine unless multiple fuzz runs deplete Alice's balance without reset.
        // setUp is called for each testFuzz_*, so Alice's balance is reset.

        uint256 mintedWhai = wHAI.deposit(depositHaiAmount, receiver); // Use original depositHaiAmount from fuzzer
        vm.stopPrank();

        // Assertions
        assertEq(hai.balanceOf(alice), aliceHaiBefore - depositHaiAmount, "FuzzDeposit: Alice HAI balance mismatch");
        assertEq(hai.balanceOf(address(wHAI)), contractHaiBefore + depositHaiAmount, "FuzzDeposit: Contract HAI balance mismatch");

        uint256 expectedWhaiMinted = (depositHaiAmount * currentPrice) / PRECISION_FACTOR;
        assertEq(mintedWhai, expectedWhaiMinted, "FuzzDeposit: Minted wHAI amount incorrect");
        assertEq(wHAI.balanceOf(receiver), receiverWhaiBefore + expectedWhaiMinted, "FuzzDeposit: Receiver wHAI balance mismatch");
        assertEq(wHAI.totalSupply(), totalSupplyBefore + expectedWhaiMinted, "FuzzDeposit: Total supply mismatch");

        assertSolvency();
    }

    // Shell for fuzzing transfers - to be implemented similarly
    function testFuzz_Transfer_Solvency(uint256 transferWhaiAmount, address toWhom) public {
        // Setup: Ensure sender has wHAI. This might involve a preliminary deposit.
        uint256 initialDepositAmount = 1000 * 1e18;
        if (aliceInitialBalance < initialDepositAmount) return; // Cannot run test if not enough base funds for setup

        vm.startPrank(alice);
        if (hai.balanceOf(alice) < initialDepositAmount) { // If Alice ran out from previous fuzz runs (not applicable if setUp runs per fuzz case)
             // This check is more for stateless fuzzing or complex sequences.
             // Given standard Foundry testing, setUp should run for each distinct fuzz input set.
             vm.stopPrank();
             return;
        }
        hai.approve(address(wHAI), initialDepositAmount);
        wHAI.deposit(initialDepositAmount, alice);
        vm.stopPrank();

        uint256 aliceWhaiBalance = wHAI.balanceOf(alice);
        vm.assume(aliceWhaiBalance > 0);
        vm.assume(transferWhaiAmount > 0 && transferWhaiAmount <= aliceWhaiBalance);
        vm.assume(toWhom != address(0) && toWhom != alice && toWhom != address(this) && toWhom != address(wHAI) && toWhom != address(hai) && toWhom != bob && toWhom != deployer);


        // Ensure price is not zero for transfer to proceed as expected by _transfer logic
        vm.prank(deployer);
        uint256 currentPrice = oracle.redemptionPrice();
        if (currentPrice == 0) {
            oracle.setRedemptionPrice(INITIAL_PRICE);
        }

        vm.startPrank(alice);
        wHAI.transfer(toWhom, transferWhaiAmount);
        vm.stopPrank();

        assertSolvency();
    }

    // Shell for fuzzing withdrawals - to be implemented similarly
    function testFuzz_Withdraw_Solvency(uint256 withdrawHaiAmount, address receiver) public {
        // Setup: Ensure sender (Alice) has wHAI/underlying HAI.
        uint256 initialDepositAmount = 1000 * 1e18;
        if (aliceInitialBalance < initialDepositAmount) return;

        vm.startPrank(alice);
        if (hai.balanceOf(alice) < initialDepositAmount) {
             vm.stopPrank();
             return;
        }
        hai.approve(address(wHAI), initialDepositAmount);
        wHAI.deposit(initialDepositAmount, alice);
        vm.stopPrank();

        vm.prank(deployer);
        uint256 currentPrice = oracle.redemptionPrice();
        if (currentPrice == 0) { // Withdraw has issues if price is 0
            oracle.setRedemptionPrice(INITIAL_PRICE); // Set to non-zero
            currentPrice = INITIAL_PRICE;
        }

        uint256 aliceWhaiBalance = wHAI.balanceOf(alice);
        // This calculation should be correct as per wHAI logic for internal balance representation
        uint256 aliceInternalHai = (aliceWhaiBalance * PRECISION_FACTOR) / currentPrice;

        vm.assume(withdrawHaiAmount > 0 && withdrawHaiAmount <= aliceInternalHai);
        vm.assume(receiver != address(0) && receiver != address(this) && receiver != address(wHAI) && receiver != address(hai) && receiver != alice && receiver != bob && receiver != deployer);


        vm.startPrank(alice);
        wHAI.withdraw(withdrawHaiAmount, receiver, alice);
        vm.stopPrank();

        assertSolvency();
    }
}
