// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;


/*
* @title ABIEncoderDemo
* @author Agustin
* @dev This smart contract shows different uses of abi.encodePacked in DeFi protocols.
*/
contract ABIEncoderDemo {

    //Events to show the codification
    event EncodedData(bytes32 indexed hash, bytes encodedData);
    
    event PoolIdentifierCreated(
        bytes32 indexed poolId, 
        address indexed token0, 
        address indexed token1, 
        uint24 fee
    );

    event UserPositionEncoded(
        bytes32 indexed userPositionId, 
        address user, 
        uint256 amount
    );

    // Custom Errors
    error ArrayLengthMismatch();
    

    /*
    * @dev Creates a pool identifier using abi.encodePacked
    * @param tokenA Address of the first token
    * @param tokenB Address of the second token
    * @param fee Fee of the pool
    * @return poolId Pool identifier (unique identifier for a pool)
    */
    function createPoolIdentifier(
        address tokenA, 
        address tokenB, 
        uint24 fee
    ) external returns (bytes32 poolId) {

        //This is done to ensure that the pool identifier is always the same, regardless of the order of the tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        bytes memory data = abi.encodePacked(
            token0, 
            token1, 
            fee
        );

        //We use abi.encodePacked to concatenate the token addresses and the fee. Creates a unique identifier for a pool
        poolId = keccak256(data);

        // Emit events
        emit PoolIdentifierCreated(poolId, token0, token1, fee);
        emit EncodedData(poolId, data);
    }


    /*
    * @dev Encodes data for a trading position
    * @param user Address of the user
    * @param tokenIn Address of the token in
    * @param tokenOut Address of the token out
    * @param amountIn Amount of the token in
    * @param minAmountOut Minimum amount of the token out
    * @return userPositionId User position identifier (unique identifier for a user position)
    * @return encodedData Encoded data for the trading position
    */
    function encodeTradingPosition(
        address user, 
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        uint256 minAmountOut, 
        uint256 deadline
    ) external returns (bytes32 userPositionId, bytes memory encodedData) {

        //Encode the position data
        encodedData = abi.encodePacked(
            user, 
            tokenIn, 
            tokenOut, 
            amountIn, 
            minAmountOut, 
            deadline
        );

        //Create a unique identifier for the user position
        userPositionId = keccak256(encodedData);

        // Emit events
        emit UserPositionEncoded(userPositionId, user, amountIn);
        emit EncodedData(userPositionId, encodedData);
    }

    /*
    * @dev Encodes data for a swap on a DEX
    * @param path Array of token addresses
    * @param amount Array of amounts
    * @param deadline Deadline for the swap
    * @return encodedData Encoded data for the swap
    */
    function encodeSwapData(
        address[] calldata path, 
        uint256[] calldata amount, 
        uint256 deadline
    ) external returns (bytes memory encodedData) {

        if (path.length != amount.length) revert ArrayLengthMismatch();

        //Encode the path
        bytes memory pathData;
        for(uint i = 0; i < path.length; i++) {
            pathData = abi.encodePacked(pathData, path[i]);
        }        

        //Encode the amounts
        bytes memory amountData;
        for(uint i = 0; i < amount.length; i++) {
            amountData = abi.encodePacked(amountData, amount[i]);
        }

        //Combine all the data
        encodedData = abi.encodePacked(
            pathData, 
            amountData, 
            deadline
        );

        emit EncodedData(keccak256(encodedData), encodedData);
    }

    /*
    * @dev Encodes data for a limit order
    * @param maker Address of the maker
    * @param taker Address of the taker
    * @param tokenIn Address of the token in
    * @param tokenOut Address of the token out
    * @param amountIn Amount of the token in
    * @param amountOut Amount of the token out
    * @param nonce Nonce for the order
    * @return orderHash Order hash (unique identifier for a limit order)
    * @return orderData Encoded data for the limit order
    */
    function encodeLimitOrder(
        address maker, 
        address taker, 
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        uint256 amountOut, 
        uint256 nonce
    ) external returns(bytes32 orderHash, bytes memory orderData){

        //Encode the order data
        orderData = abi.encodePacked(
            maker, 
            taker, 
            tokenIn, 
            tokenOut, 
            amountIn, 
            amountOut, 
            nonce, 
            "LIMIT_ORDER_V1"
        );

        //Create a unique identifier for the order
        orderHash = keccak256(orderData);

        emit EncodedData(orderHash, orderData);
    }


    /*
    * @dev Encodes data for a yield farming position
    * @param user Address of the user
    * @param poolId Pool identifier
    * @param amount Amount of the token
    * @param startTime Start time of the position
    * @return positionId Position identifier (unique identifier for a yield position)
    */
    function encodeYieldPosition(
        address user, 
        bytes32 poolId, 
        uint256 amount, 
        uint256 startTime
    ) external returns(bytes32 positionId){

        bytes memory data = abi.encodePacked(
            user, 
            poolId, 
            amount, 
            startTime, 
            "YIELD_POSITION_V1"
        );

        //Create a unique identifier for the position
        positionId = keccak256(data);

        emit EncodedData(positionId, data);
    }


    /*
    * @dev Encodes data for a flash loan
    * @param token Address of the token
    * @param amount Amount of the token
    * @param callbackData Callback data for the flash loan
    * @return flashData Encoded data for the flash loan
    */
    function encodeFlashLoanData(
        address token, 
        uint256 amount, 
        bytes calldata callbackData
    ) external returns(bytes memory flashData){

        //Encode the flash loan data
        flashData = abi.encodePacked(
            token, 
            amount, 
            callbackData, 
            "FLASH_LOAN_V1"
        );

        emit EncodedData(keccak256(flashData), flashData);
    }

    /**
    * @dev Encodes the staking pool configuration
    * @param token Address of the staking token
    * @param rewardRate Rate of rewards
    * @param lockPeriod Period of lock in seconds
    * @param maxStakers Maximum number of stakers
    * @param deadline Deadline for the pool
    * @return poolConfig Encoded pool configuration data
    */
    function encodeStakingPoolConfig(
        address token, 
        uint256 rewardRate, 
        uint256 lockPeriod, 
        uint256 maxStakers,
        uint256 deadline
    ) external returns(bytes memory poolConfig){

        //Encode the pool config data
        poolConfig = abi.encodePacked(
            token, 
            rewardRate, 
            lockPeriod, 
            maxStakers, 
            deadline
        );

        emit EncodedData(keccak256(poolConfig), poolConfig);
    }

    /**
     * @dev Creates a unique identifier for a multi-pool user
     * @param user Address of the user
     * @param poolIds Array of pool identifiers
     * @return userMultiPoolHash Unique identifier for the multi-pool user
     */
    function createUserMultiPoolHash(
        address user,
        bytes32[] calldata poolIds
    ) external returns(bytes32 userMultiPoolHash){

        bytes memory data = abi.encodePacked(user);

        for(uint i = 0; i < poolIds.length; i++) {
            data = abi.encodePacked(data, poolIds[i]);
        }

        data = abi.encodePacked(data, "MULTI_POOL_USER_V1");
        userMultiPoolHash = keccak256(data);

        emit EncodedData(userMultiPoolHash, data);
    }

    /**
     * @dev Encodes data for a yield farming position
     * @param strategyName Name of the strategy
     * @param pools Array of pool addresses
     * @param weights Array of weights
     * @return strategyData Encoded strategy data
    */
    function encodeYieldStrategy(
        string calldata strategyName, 
        address[] calldata pools, 
        uint256[] calldata weights
    ) external returns(bytes memory strategyData){
        if (pools.length != weights.length) revert ArrayLengthMismatch();

        // Encode the strategy name
        strategyData = abi.encodePacked(strategyName);

        // Encode the pools (concatenated addresses)
        for(uint i = 0; i < pools.length; i++) {
            strategyData = abi.encodePacked(strategyData, pools[i]);
        }

        // Encode the weights
        for(uint i = 0; i < weights.length; i++) {
            strategyData = abi.encodePacked(strategyData, weights[i]);
        }

        strategyData = abi.encodePacked(strategyData, "YIELD_STRATEGY_V1");

        emit EncodedData(keccak256(strategyData), strategyData);
    }


     /**
     * @dev Demonstrates encoding data for a cross-chain bridge
     * @param sourceChain Source chain
     * @param targetChain Target chain
     * @param token Token to transfer
     * @param amount Amount
     * @param recipient Recipient
     * @return bridgeData Encoded bridge data
     */
    function encodeCrossChainBridgeData(
        uint256 sourceChain,
        uint256 targetChain,
        address token,
        uint256 amount,
        address recipient
    ) external returns (bytes memory bridgeData) {
        bridgeData = abi.encodePacked(
            sourceChain,
            targetChain,
            token,
            amount,
            recipient,
            "CROSS_CHAIN_BRIDGE"
        );

        emit EncodedData(keccak256(bridgeData), bridgeData);
    }
    
    /**
     * @dev Creates a unique identifier for a DeFi transaction
     * @param txType Transaction type
     * @param user User
     * @param timestamp Timestamp
     * @param nonce Unique nonce
     * @return txId Unique transaction identifier
     */
    function createDeFiTransactionId(
        string calldata txType,
        address user,
        uint256 timestamp,
        uint256 nonce
    ) external returns (bytes32 txId) {
        bytes memory data = abi.encodePacked(
            txType,
            user,
            timestamp,
            nonce,
            "DEFI_TX"
        );
        txId = keccak256(data);

        emit EncodedData(txId, data);
    }
    
    /**
     * @dev Encodes data for a stop loss order
     * @param user User address
     * @param token Token to sell
     * @param amount Amount to sell
     * @param stopPrice Stop loss price
     * @param triggerPrice Trigger price
     * @return stopLossData Encoded order data
     */
    function encodeStopLossOrder(
        address user,
        address token,
        uint256 amount,
        uint256 stopPrice,
        uint256 triggerPrice
    ) external returns (bytes memory stopLossData) {
        stopLossData = abi.encodePacked(
            user,
            token,
            amount,
            stopPrice,
            triggerPrice,
            "STOP_LOSS_ORDER"
        );

        emit EncodedData(keccak256(stopLossData), stopLossData);
    }
    
    /**
     * @dev Encodes data for a take profit order
     * @param user User address
     * @param token Token to sell
     * @param amount Amount to sell
     * @param takeProfitPrice Take profit price
     * @return takeProfitData Encoded order data
     */
    function encodeTakeProfitOrder(
        address user,
        address token,
        uint256 amount,
        uint256 takeProfitPrice
    ) external returns (bytes memory takeProfitData) {
        takeProfitData = abi.encodePacked(
            user,
            token,
            amount,
            takeProfitPrice,
            "TAKE_PROFIT_ORDER"
        );

        emit EncodedData(keccak256(takeProfitData), takeProfitData);
    }
    
    /**
     * @dev Encodes data for a trailing stop order
     * @param user User address
     * @param token Token to sell
     * @param amount Amount to sell
     * @param trailingPercent Trailing percentage
     * @param activationPrice Activation price
     * @return trailingStopData Encoded order data
     */
    function encodeTrailingStopOrder(
        address user,
        address token,
        uint256 amount,
        uint256 trailingPercent,
        uint256 activationPrice
    ) external returns (bytes memory trailingStopData) {
        trailingStopData = abi.encodePacked(
            user,
            token,
            amount,
            trailingPercent,
            activationPrice,
            "TRAILING_STOP_ORDER"
        );

        emit EncodedData(keccak256(trailingStopData), trailingStopData);
    }

    // --- Added for Research/Benchmark purposes ---

    /**
     * @notice Returns standard ABI encoded data (32-byte padded).
     * @dev Use this for collision resistance or inter-contract calls.
     */
    function encodeStandard(address token, uint256 amount) external pure returns (bytes memory) {
        return abi.encode(token, amount);
    }

    /**
     * @notice Returns packed encoded data (minimal size).
     * @dev Use this for signature generation or tight storage packing.
     */
    function encodePacked(address token, uint256 amount) external pure returns (bytes memory) {
        return abi.encodePacked(token, amount);
    }

    /**
     * @dev Creates a unique identifier for a yield farming pool
     * @param token Address of the staking token
     * @param rewardRate Rate of rewards
     * @param timestamp Creation timestamp
     * @param chainId Chain ID
     * @return poolId Unique identifier for the pool
     */
    function createYieldPoolId(
        address token,
        uint256 rewardRate,
        uint256 timestamp,
        uint256 chainId
    ) external returns (bytes32 poolId) {
        bytes memory data = abi.encodePacked(
            token,
            rewardRate,
            timestamp,
            chainId
        );
        poolId = keccak256(data);
        emit EncodedData(poolId, data);
    }
}
