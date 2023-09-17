pragma solidity ^0.8.9;

import "../util/TestEnvironment.t.sol";

contract TreasuryTest is TestEnvironment {
    address WETH_ADMIN;

    constructor() {
        WETH_ADMIN = users[1];

        treasury = new Treasury();

        vm.prank(ALICE);
        WETH.deposit{value: 100 ether}();

        vm.prank(ALICE);
        WETH.transfer(address(treasury), 10 ether);
        treasury.sync(address(WETH), 0);

        vm.prank(master);
        treasury.grantRole(TreasuryLibrary.roleOf(address(WETH)), WETH_ADMIN);
    }

    function test_rejects_whenSendingETHToTheTreasury() external {
        vm.expectRevert();
        vm.prank(ALICE);
        payable(address(treasury)).transfer(1 ether);
    }
}

contract TreasuryTest_supportsInterface is TreasuryTest {
    function test_success() external {
        assertTrue(treasury.supportsInterface(type(IAccessControl).interfaceId));
        assertTrue(treasury.supportsInterface(type(IERC165).interfaceId));
        assertTrue(treasury.supportsInterface(type(ITreasury).interfaceId));
        assertTrue(treasury.supportsInterface(type(IKContract).interfaceId));
    }
}

contract TreasuryTest_balanceOf is TreasuryTest {
    function test_success(uint256 amount) external {
        uint256 prevBalance = treasury.balanceOf(address(WETH));

        vm.assume(amount <= ALICE.balance);

        vm.startPrank(ALICE);
        WETH.deposit{value: amount}();
        WETH.transfer(address(treasury), amount);
        vm.stopPrank();

        assertEq(treasury.balanceOf(address(WETH)), prevBalance + amount);
    }

    function test_rejects_whenCalledWithAnInvalidToken() external {
        vm.expectRevert();
        treasury.balanceOf(address(admin));
    }
}

contract TreasuryTest_roleOf is TreasuryTest {
    function test_success() external {
        assertEq(treasury.roleOf(address(WETH)), TreasuryLibrary.roleOf(address(WETH)));
    }
}

contract TreasuryTest_withdraw is TreasuryTest {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Withdraw(address indexed asset, address indexed to, uint256 amount, address indexed sender);

    function setUp() public {}

    function test_success_whenCalledByRoleAdmin(uint256 amount) external {
        uint256 prevBalance = treasury.balanceOf(address(WETH));
        amount = amount % prevBalance;

        vm.assume(amount > 0);

        vm.prank(WETH_ADMIN);
        treasury.withdraw(address(WETH), WETH_ADMIN, amount);
        assertEq(treasury.balanceOf(address(WETH)), prevBalance - amount);
    }

    function test_rejects_whenWithdrawingAnAmountGreaterThanReserves(uint256 amount) external {
        amount = amount % 90 ether;
        vm.assume(amount > 0);

        vm.prank(ALICE);
        WETH.transfer(address(treasury), amount);

        uint256 reserves = treasury.reserves(address(WETH));

        vm.expectRevert("Treasury: INSUFFICIENT_RESERVES");
        vm.prank(WETH_ADMIN);
        treasury.withdraw(address(WETH), WETH_ADMIN, reserves + amount);
    }

    function test_rejects_whenCalledByARandomAccount(address account) external {
        vm.assume(account != WETH_ADMIN);
        vm.prank(ALICE);
        vm.expectRevert();
        treasury.withdraw(address(WETH), ALICE, 1 ether);
    }

    function test_rejects_whenZeroAmount() external {
        vm.prank(WETH_ADMIN);
        vm.expectRevert("Treasury: ZERO_AMOUNT");
        treasury.withdraw(address(WETH), WETH_ADMIN, 0);
    }

    function test_shouldRevertWhenPaused() external {
        vm.prank(master);
        treasury.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        treasury.withdraw(address(WETH), WETH_ADMIN, 0);
    }

    function test_emits_Withdraw(uint256 amount) external {
        vm.prank(WETH_ADMIN);
        amount = amount % 10 ether;
        vm.assume(amount > 0);
        vm.expectEmit(true, true, true, true);
        treasury.withdraw(address(WETH), WETH_ADMIN, amount);
        emit Transfer(address(treasury), WETH_ADMIN, amount);
        emit Withdraw(address(WETH), WETH_ADMIN, amount, WETH_ADMIN);
    }
}

contract TreasuryTest_relinquish is TreasuryTest {
    event Relinquish(address indexed asset, uint256 amount, address indexed sender);

    uint256 internal treasuryWethReserve;

    function setUp() public {
        vm.startPrank(ALICE);
        WETH.deposit{value: 100 ether}();
        WETH.transfer(address(treasury), 100 ether);
        treasury.sync(address(WETH), 0);
        treasuryWethReserve = treasury.reserves(address(WETH));
        vm.stopPrank();
    }

    function test_success() external {
        vm.prank(WETH_ADMIN);
        treasury.relinquish(address(WETH), 10 ether);
        assertEq(treasury.reserves(address(WETH)), treasuryWethReserve - 10 ether);
    }

    function test_rejects_whenAmountZero() external {
        vm.prank(WETH_ADMIN);
        vm.expectRevert("Treasury: ZERO_AMOUNT");
        treasury.relinquish(address(WETH), 0);
    }

    function test_rejects_whenWithdrawingAnAmountGreaterThanReserves(uint256 amount) external {
        amount = amount % 90 ether;
        vm.assume(amount > 0);

        vm.prank(ALICE);
        WETH.transfer(address(treasury), amount);

        uint256 reserves = treasury.reserves(address(WETH));

        vm.expectRevert("Treasury: INSUFFICIENT_RESERVES");
        vm.prank(WETH_ADMIN);
        treasury.relinquish(address(WETH), reserves + amount);
    }

    function test_shouldRevertWhenPaused() external {
        vm.prank(master);
        treasury.pause();
        vm.expectRevert("Pausable: paused");
        treasury.relinquish(address(WETH), 1 ether);
    }

    function test_emits_Relinquish(uint256 amount) external {
        amount = amount % 10 ether;
        vm.assume(amount > 0);
        vm.expectEmit(true, true, true, true);

        vm.prank(WETH_ADMIN);
        treasury.relinquish(address(WETH), amount);
        assertEq(treasury.reserves(address(WETH)), treasuryWethReserve - amount);
        emit Relinquish(address(WETH), amount, WETH_ADMIN);
    }
}

contract TreasuryTest_sync is TreasuryTest {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed asset, uint256 amount, address indexed sender);

    function test_success(uint256 amount) external {
        vm.assume(amount < 90 ether);

        vm.prank(ALICE);
        WETH.transfer(address(treasury), amount);

        uint256 prevReserves = treasury.reserves(address(WETH));

        vm.prank(ALICE);
        treasury.sync(address(WETH), 0);

        assertEq(treasury.reserves(address(WETH)), prevReserves + amount);
    }

    function test_emits_Deposit(uint256 amount) external {
        vm.assume(amount < 90 ether);
        vm.assume(amount > 0);

        vm.prank(ALICE);
        WETH.transfer(address(treasury), amount);

        vm.prank(ALICE);
        vm.expectEmit(true, true, true, true);

        treasury.sync(address(WETH), 0);

        emit Deposit(address(WETH), amount, ALICE);
    }

    function test_shouldRevertWhenPaused() external {
        vm.prank(master);
        treasury.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(WETH_ADMIN);
        treasury.sync(address(WETH), 1 ether);
    }

    function test_shouldLimitTheAmountSyncedIfMaxIsGiven(uint256 amount, uint256 maxAmount) external {
        vm.assume(amount > maxAmount);
        vm.assume(amount < 90 ether);
        vm.assume(maxAmount > 0);

        vm.prank(ALICE);
        WETH.transfer(address(treasury), amount);

        uint256 synced = treasury.sync(address(WETH), maxAmount);

        assertEq(synced, maxAmount);
        assertGt(treasury.balanceOf(address(WETH)), treasury.reserves(address(WETH)));
    }

    function test_shouldSyncEverythingIfMaxAmountIsZero(uint256 amount) external {
        vm.assume(amount < 90 ether);
        vm.assume(amount > 0);

        vm.prank(ALICE);
        WETH.transfer(address(treasury), amount);

        uint256 synced = treasury.sync(address(WETH), 0);

        assertEq(synced, amount);
        assertEq(treasury.balanceOf(address(WETH)), treasury.reserves(address(WETH)));
    }
}

contract TreasuryTest_skim is TreasuryTest {
    function test_success(uint256 amount) external {
        vm.assume(amount < 90 ether);

        bytes32 role = treasury.SKIM_ROLE();
        vm.prank(master);
        treasury.grantRole(role, ALICE);

        vm.prank(ALICE);
        WETH.transfer(address(treasury), amount);

        uint256 prevBalance = treasury.balanceOf(address(WETH));

        vm.prank(ALICE);
        uint256 received = treasury.skim(address(WETH), ALICE);

        assertEq(received, amount);
        assertEq(treasury.balanceOf(address(WETH)), prevBalance - amount);
    }

    function test_shouldRevertWhenPaused() external {
        vm.prank(master);
        treasury.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(ALICE);
        treasury.skim(address(WETH), ALICE);
    }
}
