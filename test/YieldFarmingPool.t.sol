// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldFarmingPool} from "../src/YieldFarmingPool.sol";
import {ABIEncoderDemo} from "../src/ABIEncoderDemo.sol";
import {MockToken} from "../src/MockToken.sol";
import {MockRevertingToken} from "./MockRevertingToken.sol";
import {MockTokenPermit} from "./MockTokenPermit.sol";

/**
 * @title YieldFarmingPoolTest
 * @author Agustin Acosta
 * @notice Maximum coverage test suite targeting 100% branch and line coverage.
 */
contract YieldFarmingPoolTest is Test {

    YieldFarmingPool public yieldFarmingPool;
    ABIEncoderDemo public abiEncoder;
    MockToken public rewardToken;
    MockToken public stakingToken1;
    MockToken public stakingToken2;
    MockTokenPermit public permitToken;
    MockRevertingToken public failingToken;
    
    address public admin;
    address public manager;
    address public user1;
    address public user2;
    
    bytes32 public poolId1;
    bytes32 public poolId2;
    bytes32 public permitPoolId;
    bytes32 public failingPoolId;
    
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10**18;
    uint256 public constant REWARD_RATE = 1 * 10**16; 
    
    function setUp() public {
        admin = address(this);
        manager = makeAddr("manager");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        rewardToken = new MockToken("Reward Token", "RWD", INITIAL_SUPPLY);
        stakingToken1 = new MockToken("Staking Token 1", "STK1", INITIAL_SUPPLY);
        stakingToken2 = new MockToken("Staking Token 2", "STK2", INITIAL_SUPPLY);
        permitToken = new MockTokenPermit("Permit Token", "PRMT");
        failingToken = new MockRevertingToken();
        
        abiEncoder = new ABIEncoderDemo();

        yieldFarmingPool = new YieldFarmingPool(address(rewardToken), address(abiEncoder));
        yieldFarmingPool.grantRole(yieldFarmingPool.POOL_MANAGER_ROLE(), manager);
        
        stakingToken1.transfer(user1, 10000 * 10**18);
        stakingToken2.transfer(user1, 10000 * 10**18);
        permitToken.transfer(user1, 10000 * 10**18);
        failingToken.transfer(user1, 10000 * 10**18);
        rewardToken.transfer(address(yieldFarmingPool), 500000 * 10**18);
        
        poolId1 = yieldFarmingPool.createPool(address(stakingToken1), REWARD_RATE);
        vm.warp(block.timestamp + 1);
        poolId2 = yieldFarmingPool.createPool(address(stakingToken2), REWARD_RATE);
        vm.warp(block.timestamp + 1);
        permitPoolId = yieldFarmingPool.createPool(address(permitToken), REWARD_RATE);
        vm.warp(block.timestamp + 1);
        failingPoolId = yieldFarmingPool.createPool(address(failingToken), REWARD_RATE);
        
        vm.prank(user1);
        stakingToken1.approve(address(yieldFarmingPool), type(uint256).max);
        vm.prank(user1);
        stakingToken2.approve(address(yieldFarmingPool), type(uint256).max);
        vm.prank(user1);
        failingToken.approve(address(yieldFarmingPool), type(uint256).max);
    }

    // --- Constructor & Admin ---
    function test_RoleAssignment() public view {
        assertTrue(yieldFarmingPool.hasRole(yieldFarmingPool.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(yieldFarmingPool.hasRole(yieldFarmingPool.POOL_MANAGER_ROLE(), admin));
    }

    function test_RevertWhen_ConstructorRewardTokenZero() public {
        vm.expectRevert(YieldFarmingPool.InvalidRewardTokenAddress.selector);
        new YieldFarmingPool(address(0), address(abiEncoder));
    }

    // --- Create Pool Coverage ---
    function test_RevertWhen_CreatePoolTokenZero() public {
        vm.prank(manager);
        vm.expectRevert(YieldFarmingPool.InvalidTokenAddress.selector);
        yieldFarmingPool.createPool(address(0), REWARD_RATE);
    }

    function test_RevertWhen_CreatePoolRateZero() public {
        vm.prank(manager);
        vm.expectRevert(YieldFarmingPool.InvalidRewardRate.selector);
        yieldFarmingPool.createPool(address(stakingToken1), 0);
    }

    function test_RevertWhen_CreatePoolAlreadyExists() public {
        // ABIEncoder generates ID based on timestamp and chainId. 
        // We use a fixed timestamp to force collision.
        uint256 t = 9999;
        vm.warp(t);
        vm.prank(manager);
        yieldFarmingPool.createPool(address(stakingToken1), 100);
        
        vm.warp(t); // Same timestamp
        vm.prank(manager);
        vm.expectRevert(YieldFarmingPool.PoolAlreadyExists.selector);
        yieldFarmingPool.createPool(address(stakingToken1), 100);
    }

    // --- Stake Coverage ---
    function test_RevertWhen_StakeZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(YieldFarmingPool.InvalidAmount.selector);
        yieldFarmingPool.stake(poolId1, 0);
    }

    function test_RevertWhen_StakeInInactivePool() public {
        vm.prank(manager);
        yieldFarmingPool.setPoolStatus(poolId1, false);
        
        vm.prank(user1);
        vm.expectRevert(YieldFarmingPool.PoolNotActive.selector);
        yieldFarmingPool.stake(poolId1, 100);
    }

    function test_Stake_AutoClaimBranchAtSecondStake() public {
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, 100 * 10**18);
        
        vm.warp(block.timestamp + 100);
        
        // This second stake should trigger rewards claim branch
        uint256 balanceBefore = rewardToken.balanceOf(user1);
        yieldFarmingPool.stake(poolId1, 50 * 10**18);
        uint256 balanceAfter = rewardToken.balanceOf(user1);
        
        assertGt(balanceAfter, balanceBefore, "Should have auto-claimed rewards");
        vm.stopPrank();
    }

    function test_RevertWhen_StakeInsufficientRewardsInContract() public {
        // Drain reward tokens
        vm.prank(admin);
        yieldFarmingPool.rescueTokens(address(rewardToken), rewardToken.balanceOf(address(yieldFarmingPool)));
        
        vm.prank(user1);
        yieldFarmingPool.stake(poolId1, 100);
        
        vm.warp(block.timestamp + 100);
        
        vm.prank(user1);
        // Should revert because it tries to auto-claim 
        vm.expectRevert(YieldFarmingPool.InsufficientRewardBalance.selector);
        yieldFarmingPool.stake(poolId1, 100);
    }

    // --- Withdraw Coverage ---
    function test_RevertWhen_WithdrawZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(YieldFarmingPool.InvalidAmount.selector);
        yieldFarmingPool.withdraw(poolId1, 0);
    }

    function test_RevertWhen_WithdrawInsufficientStaked() public {
        vm.prank(user1);
        yieldFarmingPool.stake(poolId1, 100);
        
        vm.prank(user1);
        vm.expectRevert(YieldFarmingPool.InsufficientStakedAmount.selector);
        yieldFarmingPool.withdraw(poolId1, 101);
    }

    function test_Withdraw_WithRewardsBranch() public {
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, 100);
        vm.warp(block.timestamp + 100);
        
        uint256 beforeBal = rewardToken.balanceOf(user1);
        yieldFarmingPool.withdraw(poolId1, 100);
        uint256 afterBal = rewardToken.balanceOf(user1);
        
        assertGt(afterBal, beforeBal, "Should claim rewards on withdrawal");
        vm.stopPrank();
    }

    // --- Claim Rewards Coverage ---
    function test_RevertWhen_ClaimNoRewardsPending() public {
        vm.prank(user1);
        vm.expectRevert(YieldFarmingPool.NoPendingRewards.selector);
        yieldFarmingPool.claimRewards(poolId1);
    }

    // --- Update Rate & Status Coverage ---
    function test_RevertWhen_UpdateRateOnInactivePool() public {
        vm.prank(manager);
        yieldFarmingPool.setPoolStatus(poolId1, false);
        
        vm.prank(manager);
        vm.expectRevert(YieldFarmingPool.PoolNotActive.selector);
        yieldFarmingPool.updatePoolRewardRate(poolId1, 500);
    }

    function test_RevertWhen_UpdateRateZero() public {
        vm.prank(manager);
        vm.expectRevert(YieldFarmingPool.InvalidRewardRate.selector);
        yieldFarmingPool.updatePoolRewardRate(poolId1, 0);
    }

    function test_RevertWhen_RescueStakingToken_MultiplePoolsCheck() public {
        // We have poolId1 and poolId2. Verify it checks both in the loop.
        vm.expectRevert(YieldFarmingPool.CannotRescueStakingToken.selector);
        yieldFarmingPool.rescueTokens(address(stakingToken2), 100);
    }

    function test_RescueTokens_Success() public {
        MockToken other = new MockToken("Other", "OT", 1000);
        other.transfer(address(yieldFarmingPool), 500);
        uint256 balBefore = other.balanceOf(admin);
        
        vm.prank(admin);
        yieldFarmingPool.rescueTokens(address(other), 500);
        assertEq(other.balanceOf(admin), balBefore + 500);
    }

    // --- View Functions Coverage ---
    function test_ViewFunctions_Coverage() public view {
        yieldFarmingPool.getActivePoolsSize();
        yieldFarmingPool.getActivePools();
        yieldFarmingPool.getUserHash(poolId1, user1);
        yieldFarmingPool.getPoolEncodedData(poolId1);
    }

    function test_CalculatePending_SameTimestampBranch() public {
        vm.prank(user1);
        yieldFarmingPool.stake(poolId1, 100);
        
        // At the same block timestamp, pending should be 0 and the internal branch should be false
        uint256 pending = yieldFarmingPool.pendingRewards(poolId1, user1);
        assertEq(pending, 0);
    }

    function test_UpdatePool_ZeroStakeBranch() public {
        // This hits the 'else' in _updatePool when totalStaked is 0
        vm.warp(block.timestamp + 100);
        vm.prank(manager);
        yieldFarmingPool.updatePoolRewardRate(poolId1, 200);
    }

    function test_Stake_SecondStakeSameBlock_ZeroAccruedBranch() public {
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, 100);
        
        // Stake again in the SAME block. user.amount > 0, but accrued is 0.
        // This hits the 'amount > 0' branch but 'accrued > 0' is false.
        yieldFarmingPool.stake(poolId1, 50);
        vm.stopPrank();
    }

    function test_ClaimRewards_Success() public {
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, 100 * 10**18);
        
        vm.warp(block.timestamp + 100);
        
        uint256 balBefore = rewardToken.balanceOf(user1);
        yieldFarmingPool.claimRewards(poolId1);
        
        assertGt(rewardToken.balanceOf(user1), balBefore, "Claimed rewards successfully");
        vm.stopPrank();
    }

    // --- Fuzz Tests (Linearity & Resilience) ---
    function testFuzz_Stake_Dynamic(uint256 amount) public {
        amount = bound(amount, 1e6, 10000 * 10**18); 
        vm.prank(user1);
        yieldFarmingPool.stake(poolId1, amount);
        (uint256 userAmount,,) = yieldFarmingPool.userInfo(poolId1, user1);
        assertEq(userAmount, amount);
    }

    function testFuzz_RewardAccrual_Dynamic(uint256 stakeAmount, uint32 timeElapsed) public {
        stakeAmount = bound(stakeAmount, 1e18, 1000 * 10**18); 
        timeElapsed = uint32(bound(timeElapsed, 1, 365 days)); 
        
        vm.prank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);
        
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 expectedRewards = uint256(timeElapsed) * REWARD_RATE;
        uint256 accrued = yieldFarmingPool.pendingRewards(poolId1, user1);
        
        assertApproxEqAbs(accrued, expectedRewards, 1e10);
    }

    // --- EIP-2612 Permit Coverage ---
    function test_StakeWithPermit_Success() public {
        uint256 amount = 50 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 pk = 0xA11CE;
        address signer = vm.addr(pk);
        permitToken.transfer(signer, amount);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            pk,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    permitToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                            signer,
                            address(yieldFarmingPool),
                            amount,
                            permitToken.nonces(signer),
                            deadline
                        )
                    )
                )
            )
        );

        vm.prank(signer);
        yieldFarmingPool.stakeWithPermit(permitPoolId, amount, deadline, v, r, s);
        (uint256 uAmt,,) = yieldFarmingPool.userInfo(permitPoolId, signer);
        assertEq(uAmt, amount);
    }
}
