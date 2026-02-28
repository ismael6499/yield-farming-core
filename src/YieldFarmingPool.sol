// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ABIEncoderDemo} from "./ABIEncoderDemo.sol";

/**
 * @title YieldFarmingPool
 * @author Agustin Acosta
 * @notice A high-performance, secure yield farming protocol for ERC20 tokens.
 * @dev Implementation features:
 * - Gas-optimized storage packing (Slot usage reduced from 6 to 4).
 * - Multi-role AccessControl for decentralized administrative management.
 * - EIP-2612 Permit support for one-transaction staking experience.
 * - Fee-on-transfer token compatibility via balance delta checks.
 * - Guarded reward accrual to prevent silent reward loss for users.
 * - Administrative guardrails preventing the rescue of staking assets.
 */
contract YieldFarmingPool is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * @dev Role identifier for pool management operations.
     * Managers can create pools, update rates and toggle active status.
     */
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    /**
     * @dev Internal pool accounting structure.
     * Packed for gas efficiency: token (20) + isActive (1) + lastUpdateTime (8) = 29 bytes.
     */
    struct Pool {
        address token;              
        bool isActive;               
        uint64 lastUpdateTime;       
        uint256 totalStaked;         
        uint256 rewardRate;          
        uint256 rewardPerTokenStored;
    }

    /**
     * @dev User-specific staking and reward information.
     */
    struct UserInfo {  
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastClaimTime;
    }

    /// @notice The token distributed as rewards across all pools.
    IERC20 public immutable rewardToken;
    
    /// @notice External helper for standardized ABI encoding and identifiers.
    ABIEncoderDemo public immutable abiEncoder;

    /// @notice Array of all generated pool identifiers for off-chain and on-chain discovery.
    bytes32[] public activePools;
    
    /// @notice Mapping from unique pool IDs to their respective state and configuration.
    mapping(bytes32 => Pool) public pools;
    
    /// @notice Mapping tracking user interaction and positions per pool.
    mapping(bytes32 => mapping(address => UserInfo)) public userInfo;

    // --- Events ---
    event PoolCreated(bytes32 indexed poolId, address indexed token, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event PoolUpdated(bytes32 indexed poolId, uint256 newRewardRate);
    event PoolStatusUpdated(bytes32 indexed poolId, bool isActive);
    event TokensRescued(address indexed token, uint256 amount);

    // --- Custom Errors ---
    error InvalidRewardTokenAddress();
    error InvalidTokenAddress();
    error InvalidRewardRate();
    error PoolAlreadyExists();
    error PoolNotActive();
    error InvalidAmount();
    error InsufficientStakedAmount();
    error NoPendingRewards();
    error InsufficientRewardBalance();
    error CannotRescueStakingToken();

    /**
     * @notice Initializes the protocol set with reward token and helper addresses.
     * @param rewardTokenAddress_ The ERC20 token to be distributed.
     * @param abiEncoderAddress_ Helper contract address for ABI encoding.
     */
    constructor(address rewardTokenAddress_, address abiEncoderAddress_) {
        if (rewardTokenAddress_ == address(0)) revert InvalidRewardTokenAddress();
        
        rewardToken = IERC20(rewardTokenAddress_);
        abiEncoder = ABIEncoderDemo(abiEncoderAddress_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POOL_MANAGER_ROLE, msg.sender);
    }
    
    /**
     * @notice Provisions a new staking pool for a specific asset.
     * @dev Permission restricted to POOL_MANAGER_ROLE.
     * @param tokenAddress The ERC20 address of the asset users will stake.
     * @param rewardRate Tokens per second to be shared among participants.
     * @return poolId The generated unique identifier for the pool.
     */
    function createPool(address tokenAddress, uint256 rewardRate) 
        external 
        onlyRole(POOL_MANAGER_ROLE) 
        returns (bytes32 poolId)
    {
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        if (rewardRate == 0) revert InvalidRewardRate();

        poolId = abiEncoder.createYieldPoolId(
            tokenAddress,
            rewardRate,
            block.timestamp,
            block.chainid
        );

        if (pools[poolId].token != address(0)) revert PoolAlreadyExists();

        pools[poolId] = Pool({
            token: tokenAddress,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: uint64(block.timestamp),
            rewardPerTokenStored: 0,
            isActive: true
        });

        activePools.push(poolId);
        emit PoolCreated(poolId, tokenAddress, rewardRate);
    }

    /**
     * @notice Deposits staking assets into a pool to earn rewards.
     * @dev Requires caller to have previously approved the contract.
     * @param poolId The identifier of the target pool.
     * @param amount The quantity of tokens to deposit.
     */
    function stake(bytes32 poolId, uint256 amount) external nonReentrant {
        _stake(poolId, msg.sender, amount);
    }

    /**
     * @notice Deposits assets using EIP-2612 Permit for a single-transaction experience.
     * @dev Improves UX by providing approval and stake in one block. Fails if token is non-compliant.
     * @param poolId The identifier of the target pool.
     * @param amount The quantity of tokens to deposit.
     * @param deadline Expiration timestamp for the signature.
     * @param v ECDSA signature component.
     * @param r ECDSA signature component.
     * @param s ECDSA signature component.
     */
    function stakeWithPermit(
        bytes32 poolId,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        Pool storage pool = pools[poolId];
        IERC20Permit(pool.token).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _stake(poolId, msg.sender, amount);
    }

    /**
     * @dev Internal shared logic for staking. Incorporates Fee-on-transfer protection.
     * @param poolId Pool ID.
     * @param account Wallet of the user.
     * @param amount Amount targeted for stake.
     */
    function _stake(bytes32 poolId, address account, uint256 amount) internal {
        Pool storage pool = pools[poolId];
        
        if (!pool.isActive) revert PoolNotActive();
        if (amount == 0) revert InvalidAmount();
        
        _updatePool(poolId);
        
        UserInfo storage user = userInfo[poolId][account];
        
        // Auto-claim pending rewards before position change
        if(user.amount > 0) {
            uint256 accrued = _calculatePendingRewards(poolId, account);
            if(accrued > 0) {
                if (!_safeRewardsTransfer(account, accrued)) revert InsufficientRewardBalance();
                emit RewardClaimed(poolId, account, accrued);
            }
        }

        // Measure actual transferred tokens to handle fee-on-transfer assets
        uint256 balBefore = IERC20(pool.token).balanceOf(address(this));
        IERC20(pool.token).safeTransferFrom(account, address(this), amount);
        uint256 balAfter = IERC20(pool.token).balanceOf(address(this));
        uint256 actualAmountReceived = balAfter - balBefore;

        user.amount += actualAmountReceived;
        user.rewardDebt = (user.amount * pool.rewardPerTokenStored) / 1e18;
        user.lastClaimTime = block.timestamp;
        pool.totalStaked += actualAmountReceived;

        emit Staked(poolId, account, actualAmountReceived);
    }

    /**
     * @notice Withdraws principal and accrued rewards from a pool.
     * @dev Users can withdraw even from inactive pools.
     * @param poolId The identifier of the pool.
     * @param amount Quantity of staked tokens to retrieve.
     */
    function withdraw(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        if (amount == 0) revert InvalidAmount();
        
        _updatePool(poolId);
        UserInfo storage user = userInfo[poolId][msg.sender];
        if(user.amount < amount) revert InsufficientStakedAmount();

        uint256 accrued = _calculatePendingRewards(poolId, msg.sender);
        if(accrued > 0) {
            if (!_safeRewardsTransfer(msg.sender, accrued)) revert InsufficientRewardBalance();
            emit RewardClaimed(poolId, msg.sender, accrued);
        }

        user.amount -= amount;
        user.rewardDebt = (user.amount * pool.rewardPerTokenStored) / 1e18;
        user.lastClaimTime = block.timestamp;
        pool.totalStaked -= amount;

        IERC20(pool.token).safeTransfer(msg.sender, amount);
        emit Withdrawn(poolId, msg.sender, amount);
    }

    /**
     * @notice Harvests all pending rewards accumulated for the user in a pool.
     * @dev Does not affect the staked principal. Reverts if nothing is due.
     * @param poolId The identifier of the pool.
     */
    function claimRewards(bytes32 poolId) external nonReentrant {
        _updatePool(poolId);
        
        uint256 accrued = _calculatePendingRewards(poolId, msg.sender);
        if(accrued == 0) revert NoPendingRewards();

        UserInfo storage user = userInfo[poolId][msg.sender];
        user.rewardDebt = (user.amount * pools[poolId].rewardPerTokenStored) / 1e18;
        user.lastClaimTime = block.timestamp;
        
        if (!_safeRewardsTransfer(msg.sender, accrued)) revert InsufficientRewardBalance();
        emit RewardClaimed(poolId, msg.sender, accrued);
    }

    /**
     * @notice Dynamically adjusts the reward emission for a pool.
     * @dev Only callable by POOL_MANAGER_ROLE. Accrues pending rewards before update.
     * @param poolId Pool ID to update.
     * @param newRewardRate New amount of tokens per second.
     */
    function updatePoolRewardRate(bytes32 poolId, uint256 newRewardRate) 
        external 
        onlyRole(POOL_MANAGER_ROLE) 
    {
        Pool storage pool = pools[poolId];
        if (!pool.isActive) revert PoolNotActive();
        if (newRewardRate == 0) revert InvalidRewardRate();
        
        _updatePool(poolId);
        pool.rewardRate = newRewardRate;
        
        emit PoolUpdated(poolId, newRewardRate);
    }   

    /**
     * @notice Toggles a pool between Active and Paused states.
     * @dev Only callable by POOL_MANAGER_ROLE.
     * @param poolId Pool ID.
     * @param isActive Desired status.
     */
    function setPoolStatus(bytes32 poolId, bool isActive) external onlyRole(POOL_MANAGER_ROLE) {
        pools[poolId].isActive = isActive;
        emit PoolStatusUpdated(poolId, isActive);
    }   

    /**
     * @notice Extracts accidentally sent tokens from the contract balance.
     * @dev SECURITY GUARD: Reverts if attempting to withdraw staking assets to protect user deposits.
     * @param token Address of the token to rescue.
     * @param amount Quantity to extract.
     */
    function rescueTokens(address token, uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        for(uint i = 0; i < activePools.length; i++) {
            if(pools[activePools[i]].token == token) revert CannotRescueStakingToken();
        }

        IERC20(token).safeTransfer(msg.sender, amount);
        emit TokensRescued(token, amount);
    }

    /**
     * @dev Internal accounting update logic. Syncs virtual rewards with current timestamp.
     * @param poolId Targeted pool.
     */
    function _updatePool(bytes32 poolId) internal {
        Pool storage pool = pools[poolId];
        
        if (pool.totalStaked > 0) {
            uint256 elapsedTime = block.timestamp - uint256(pool.lastUpdateTime);
            uint256 rewards = elapsedTime * pool.rewardRate;
            pool.rewardPerTokenStored += (rewards * 1e18) / pool.totalStaked;
        }
        pool.lastUpdateTime = uint64(block.timestamp);
    }

    /**
     * @dev Mathematically calculates all pending rewards available for a user.
     * @param poolId Pool ID.
     * @param userAddress Beneficiary address.
     * @return pending Total tokens due since last claim.
     */
    function _calculatePendingRewards(bytes32 poolId, address userAddress) internal view returns(uint256){
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][userAddress];

        uint256 rewardPerToken = pool.rewardPerTokenStored;
        uint256 lastUpdate = uint256(pool.lastUpdateTime);
        
        if (block.timestamp > lastUpdate && pool.totalStaked > 0) {
            uint256 elapsedTime = block.timestamp - lastUpdate;
            uint256 rewards = elapsedTime * pool.rewardRate;
            rewardPerToken += (rewards * 1e18) / pool.totalStaked;
        }

        return (user.amount * rewardPerToken / 1e18) - user.rewardDebt;
    }

    /**
     * @dev Secure transfer wrapper. Ensures contract has enough liquidity.
     * @param to Recipient.
     * @param amount Tokens to send.
     * @return success Boolean indicating if liquidity was sufficient.
     */
    function _safeRewardsTransfer(address to, uint256 amount) internal returns (bool) {
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (amount > rewardBalance) return false;
        
        rewardToken.safeTransfer(to, amount);
        return true;
    }

    // --- View Functions ---

    /**
     * @notice Returns the amount of rewards currently claimable by an account.
     * @param poolId Pool ID.
     * @param user Account address.
     * @return Total pending reward tokens.
     */
    function pendingRewards(bytes32 poolId, address user) external view returns (uint256) {
        return _calculatePendingRewards(poolId, user);
    }

    /**
     * @notice Provides full pool configuration in a single call.
     * @param poolId Unique identifier for the pool.
     * @return Encoded bytes array containing pool configuration.
     */
    function getPoolEncodedData(bytes32 poolId) external view returns(bytes memory){
        Pool storage pool = pools[poolId];
        return abiEncoder.encodePoolData(
            pool.token,
            pool.totalStaked,
            pool.rewardRate,
            pool.lastUpdateTime,
            pool.rewardPerTokenStored,
            pool.isActive
        );
    }

    /**
     * @notice Returns the total count of pools ever created.
     */
    function getActivePoolsSize() external view returns(uint256) {
        return activePools.length;
    }

    /**
     * @notice Returns the list of all pool identifiers.
     */
    function getActivePools() external view returns(bytes32[] memory) {
        return activePools;
    }

    /**
     * @notice Generates a unique user interaction hash for off-chain verification.
     */
    function getUserHash(bytes32 poolId, address user) external view returns(bytes32) {
        return abiEncoder.encodeYieldUserHash(poolId, user);
    }
}