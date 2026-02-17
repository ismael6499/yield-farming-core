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
    






}