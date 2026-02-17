// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./ABIEncoderDemo.sol";

/**
 * @title YieldFarmingPool
 * @author Agustin Acosta
 * @dev This smart contract is a yield farming pool used for testing the yield farming protocol and for demonstrating the use of abi.encodePacked to encode pool parameters and calculate unique identifiers
 */
contract YieldFarmingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Struct to store pool data
    struct Pool {
        address token;
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        bool isActive;
    }

    struct UserInfo {  
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastClaimTime;
    }

    IERC20 public immutable rewardToken;
    ABIEncoderDemo public immutable abiEncoder;

    //List of all active pools
    bytes32[] public activePools;

    // Mappings
    mapping(bytes32 => Pool) public pools;

    // Mapping to store user information by pool and address
    mapping(bytes32 => mapping(address => UserInfo)) public userInfo;

    // Events
    event PoolCreated(bytes32 indexed poolId, address indexed token, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event PoolUpdated(bytes32 indexed poolId, uint256 newRewardRate);

    // Errors
    error InvalidRewardTokenAddress();
    error InvalidTokenAddress();
    error InvalidRewardRate();
    error PoolAlreadyExists();
    error PoolNotActive();
    error InvalidAmount();
    error InsufficientStakedAmount();

    /*
    * @dev Constructor
    * @param rewardTokenAddress_ Address of the reward token
    */
    constructor(address rewardTokenAddress_, address abiEncoderAddress_) Ownable(msg.sender) {
        if (rewardTokenAddress_ == address(0)) {
            revert InvalidRewardTokenAddress();
        }
        rewardToken = IERC20(rewardTokenAddress_);
        abiEncoder = ABIEncoderDemo(abiEncoderAddress_);
    }
    
    /*
    * @dev Creates a new yield farming pool
    * @param tokenAddress Address of the token to be staked
    * @param rewardRate Rate of reward per second
    * @return poolId Pool identifier
    */ 
    function createPool(address tokenAddress, uint256 rewardRate) external onlyOwner returns (bytes32 poolId){
        if (tokenAddress == address(0)) {
            revert InvalidTokenAddress();
        }
        if (rewardRate == 0) {
            revert InvalidRewardRate();
        }

        poolId = abiEncoder.createYieldPoolId(
            tokenAddress,
            rewardRate,
            block.timestamp,
            block.chainid
        );

        if (pools[poolId].token != address(0)) {
            revert PoolAlreadyExists();
        }

        pools[poolId] = Pool({
            token: tokenAddress,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            isActive: true
        });

        activePools.push(poolId);

        emit PoolCreated(poolId, tokenAddress, rewardRate);
    }

    /*
    * @dev Stakes tokens in a pool
    * @param poolId Pool identifier
    * @param amount Amount of tokens to stake
    */
    function stake(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        
        if (!pool.isActive) {
            revert PoolNotActive();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        
        _updatePool(poolId);
        
        UserInfo storage user = userInfo[poolId][msg.sender];
        
        if(user.amount > 0) {
            uint256 pendingRewards = _calculatePendingRewards(poolId, msg.sender);
            if(pendingRewards > 0) {
                _safeRewardsTransfer(msg.sender, pendingRewards);
                emit RewardClaimed(poolId, msg.sender, pendingRewards);
            }
        }

        // Transfer tokens from user to pool
        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amount);

        // Update user information
        user.amount += amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;

        // Update pool information
        pool.totalStaked += amount;

        emit Staked(poolId, msg.sender, amount);
    }

    /*
    * @dev Withdraws staked tokens from a pool
    * @param poolId Pool identifier
    * @param amount Amount of tokens to withdraw
    */
    function withdraw(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        
        if (!pool.isActive) {
            revert PoolNotActive();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        
        _updatePool(poolId);
        
        UserInfo storage user = userInfo[poolId][msg.sender];
        
        if(user.amount < amount) {
            revert InsufficientStakedAmount();
        }

        uint256 pendingRewards = _calculatePendingRewards(poolId, msg.sender);
        if(pendingRewards > 0) {
            _safeRewardsTransfer(msg.sender, pendingRewards);
            emit RewardClaimed(poolId, msg.sender, pendingRewards);
        }

        // Update user information
        user.amount -= amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;

        // Update pool information
        pool.totalStaked -= amount;

        //Transfer tokens from pool to user
        IERC20(pool.token).safeTransfer(msg.sender, amount);

        emit Withdrawn(poolId, msg.sender, amount);
    }

    /*
    * @dev Claims rewards from a pool
    * @param poolId Pool identifier
    */
    function claimRewards(bytes32 poolId) external nonReentrant {
        _updatePool(poolId);

        
        uint256 pendingRewards = _calculatePendingRewards(poolId, msg.sender);

        if(pendingRewards < 0) {
            revert NoPendingRewards();
        }

        UserInfo storage user = userInfo[poolId][msg.sender];
        
        user.rewardDebt = user.amount * pools[poolId].rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;
        
        _safeRewardsTransfer(msg.sender, pendingRewards);
        emit RewardClaimed(poolId, msg.sender, pendingRewards);
    }

    /*
    * @dev Updates the reward rate of a pool
    * @param poolId Pool identifier
    * @param newRewardRate New reward rate
    */
    function updatePoolRewardRate(bytes32 poolId, uint256 newRewardRate) external onlyOwner {
        Pool storage pool = pools[poolId];
        
        if (!pool.isActive) {
            revert PoolNotActive();
        }

        if (newRewardRate == 0) {
            revert InvalidRewardRate();
        }
        
        _updatePool(poolId);
        pool.rewardRate = newRewardRate;
        
        emit PoolUpdated(poolId, newRewardRate);
    }   


    /* 
    * @dev Gets the encoded data of a pool
    * @param poolId Pool identifier
    * @return encodedData Encoded data of the pool
    */
    function getPoolEncodedData(bytes32 poolId) external view returns(bytes memory encodedData){
        Pool storage pool = pools[poolId];
        
        encodedData = abiEncoder.encodePoolData(
            pool.token,
            pool.totalStaked,
            pool.rewardRate,
            pool.lastUpdateTime,
            pool.rewardPerTokenStored,
            pool.isActive
        );
    }

    /**
    * @dev Create a unique hash for a user in a specific pool
    * @param poolId Pool identifier
    * @param user User address
    * @return userHash Unique user hash
    */
    function getUserHash(bytes32 poolId, address user) external view returns(bytes32 userHash){
        userHash = abiEncoder.encodeYieldUserHash(poolId, user);
    }

    function getActivePoolsSize() external view returns(uint256 size){
        size = activePools.length;
    }

    function getActivePools() external view returns(bytes[] memory){
        return activePools;
    }

    function getActivePoolId(uint256 index) external view returns(bytes32 poolId){
        poolId = activePools[index];
    }


    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

}