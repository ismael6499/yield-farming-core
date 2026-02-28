//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/ABIEncoderDemo.sol";


/// @title ABIEncoderDemoTest
/// @notice Comprehensive tests suite targeting 100% coverage for ABIEncoderDemo contract
contract ABIEncoderDemoTest is Test {
    ABIEncoderDemo private abiEncoderDemo;

    /// @dev Deploys a fresh contract before each test
    function setUp() public {
        abiEncoderDemo = new ABIEncoderDemo();
    }

    /// @dev Pool id must be invariant to the order of the tokens, tokens are sorted internally
    function test_createPoolIdentifier_SameForBothTokenOrders() external {
        address tokenA = address(0x1000);
        address tokenB = address(0x2000);
        uint24 fee = 3000;

        bytes32 poolId1 = abiEncoderDemo.createPoolIdentifier(tokenA, tokenB, fee);
        bytes32 poolId2 = abiEncoderDemo.createPoolIdentifier(tokenB, tokenA, fee);

        assertEq(poolId1, poolId2, "Pool id must be invariant to the order of the tokens");
    }

    /**
     * @dev Fuzz test to ensure pool ID invariance for any pair of addresses and fees.
     */
    function testFuzz_createPoolIdentifier_Invariance(address t1, address t2, uint24 fee) public {
        bytes32 id1 = abiEncoderDemo.createPoolIdentifier(t1, t2, fee);
        bytes32 id2 = abiEncoderDemo.createPoolIdentifier(t2, t1, fee);
        assertEq(id1, id2, "Invariance failed for random addresses/fees");
    }

    
    function test_createPoolIdentifier_DifferentFeeDifferentPoolId() external {
        address tokenA = address(0x1000);
        address tokenB = address(0x2000);
        uint24 fee1 = 3000;
        uint24 fee2 = 500;

        bytes32 poolId1 = abiEncoderDemo.createPoolIdentifier(tokenA, tokenB, fee1);
        bytes32 poolId2 = abiEncoderDemo.createPoolIdentifier(tokenA, tokenB, fee2);

        assertNotEq(poolId1, poolId2, "Pool id must be different for different fees");
    }

    function test_encodeTradingPosition_ReturnsExpectedDataAndHash() external {
        address user = address(0x1000);
        address tokenIn = address(0x2000);
        address tokenOut = address(0x3000);
        uint256 amountIn = 1 ether;
        uint256 minAmountOut = 2 ether;
        uint256 deadline = block.timestamp + 1 days;

        (bytes32 userPositionId, bytes memory encodedData) = abiEncoderDemo.encodeTradingPosition(user, tokenIn, tokenOut, amountIn, minAmountOut, deadline);


        assertEq(encodedData, abi.encodePacked(user, tokenIn, tokenOut, amountIn, minAmountOut, deadline), "Encoded data must match the expected data");
        assertEq(userPositionId, keccak256(encodedData), "User position id must match the hash of the encoded data");
    }   


    function test_encodeSwapData_EncodesPathAmountDeadline() external {
        address[] memory path = new address[](3);
        path[0] = address(0x1000);
        path[1] = address(0x2000);
        path[2] = address(0x3000);
        uint256[] memory amount = new uint256[](3);
        amount[0] = 1 ether;
        amount[1] = 2 ether;
        amount[2] = 3 ether;
        uint256 deadline = block.timestamp + 1 days;

        bytes memory encodedData = abiEncoderDemo.encodeSwapData(path, amount, deadline);

        bytes memory expectedPathData;
        for(uint i = 0; i < path.length; i++) {
            expectedPathData = abi.encodePacked(expectedPathData, path[i]);
        }
        bytes memory expectedAmountData;
        for(uint i = 0; i < amount.length; i++) {
            expectedAmountData = abi.encodePacked(expectedAmountData, amount[i]);
        }
        bytes memory expectedEncodedData = abi.encodePacked(expectedPathData, expectedAmountData, deadline);

        assertEq(encodedData, expectedEncodedData, "Encoded data must match the expected data");
        assertEq(keccak256(encodedData), keccak256(expectedEncodedData), "Hash must match");
    }

    function test_RevertWhen_SwapDataLengthsMismatch() external {
        address[] memory path = new address[](3);
        path[0] = address(0x1000);
        path[1] = address(0x2000);
        path[2] = address(0x3000);
        uint256[] memory amount = new uint256[](2);
        amount[0] = 1 ether;
        amount[1] = 2 ether;
        uint256 deadline = block.timestamp + 1 days;

        vm.expectRevert(ABIEncoderDemo.ArrayLengthMismatch.selector);
        abiEncoderDemo.encodeSwapData(path, amount, deadline);
    }

    function test_encodeLimitOrder() external {
        address maker = address(0x1000);
        address taker = address(0x2000);
        address tokenIn = address(0x3000);
        address tokenOut = address(0x4000);
        uint256 amountIn = 1 ether;
        uint256 amountOut = 2 ether;
        uint256 nonce = 123;

        (bytes32 orderHash, bytes memory orderData) = abiEncoderDemo.encodeLimitOrder(
            maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce
        );

        bytes memory expectedData = abi.encodePacked(
            maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce, "LIMIT_ORDER_V1"
        );
        assertEq(orderData, expectedData);
        assertEq(orderHash, keccak256(expectedData));
    }

    function test_encodeYieldPosition() external {
        address user = address(0x1000);
        bytes32 poolId = keccak256("pool");
        uint256 amount = 1 ether;
        uint256 startTime = block.timestamp;

        bytes32 positionId = abiEncoderDemo.encodeYieldPosition(user, poolId, amount, startTime);

        bytes memory expectedData = abi.encodePacked(
            user, poolId, amount, startTime, "YIELD_POSITION_V1"
        );
        assertEq(positionId, keccak256(expectedData));
    }

    function test_encodeFlashLoanData() external {
        address token = address(0x1000);
        uint256 amount = 1 ether;
        bytes memory callbackData = hex"1234";

        bytes memory flashData = abiEncoderDemo.encodeFlashLoanData(token, amount, callbackData);

        bytes memory expectedData = abi.encodePacked(
            token, amount, callbackData, "FLASH_LOAN_V1"
        );
        assertEq(flashData, expectedData);
    }

    function test_encodeStakingPoolConfig() external {
        address token = address(0x1000);
        uint256 rewardRate = 5;
        uint256 lockPeriod = 1 days;
        uint256 maxStakers = 100;
        uint256 deadline = block.timestamp + 30 days;

        bytes memory poolConfig = abiEncoderDemo.encodeStakingPoolConfig(
            token, rewardRate, lockPeriod, maxStakers, deadline
        );

        bytes memory expectedData = abi.encodePacked(
            token, rewardRate, lockPeriod, maxStakers, deadline
        );
        assertEq(poolConfig, expectedData);
    }

    function test_createUserMultiPoolHash() external {
        address user = address(0x1000);
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = keccak256("pool1");
        poolIds[1] = keccak256("pool2");

        bytes32 userMultiPoolHash = abiEncoderDemo.createUserMultiPoolHash(user, poolIds);

        bytes memory expectedData = abi.encodePacked(user);
        for(uint i=0; i<poolIds.length; i++){
            expectedData = abi.encodePacked(expectedData, poolIds[i]);
        }
        expectedData = abi.encodePacked(expectedData, "MULTI_POOL_USER_V1");

        assertEq(userMultiPoolHash, keccak256(expectedData));
    }

    function test_encodeYieldStrategy_HappyPath() external {
        string memory strategyName = "StrategyA";
        address[] memory pools = new address[](2);
        pools[0] = address(0x10);
        pools[1] = address(0x20);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 50;
        weights[1] = 50;

        bytes memory strategyData = abiEncoderDemo.encodeYieldStrategy(strategyName, pools, weights);

        bytes memory expectedData = abi.encodePacked(strategyName);
        for(uint i=0; i<pools.length; i++){
            expectedData = abi.encodePacked(expectedData, pools[i]);
        }
        for(uint i=0; i<weights.length; i++){
            expectedData = abi.encodePacked(expectedData, weights[i]);
        }
        expectedData = abi.encodePacked(expectedData, "YIELD_STRATEGY_V1");

        assertEq(strategyData, expectedData);
    }

    function test_RevertWhen_YieldStrategyLengthsMismatch() external {
        string memory strategyName = "StrategyA";
        address[] memory pools = new address[](2);
        uint256[] memory weights = new uint256[](1);

        vm.expectRevert(ABIEncoderDemo.ArrayLengthMismatch.selector);
        abiEncoderDemo.encodeYieldStrategy(strategyName, pools, weights);
    }

    function test_encodeCrossChainBridgeData() external {
        uint256 sourceChain = 1;
        uint256 targetChain = 2;
        address token = address(0x1000);
        uint256 amount = 1 ether;
        address recipient = address(0x2000);

        bytes memory bridgeData = abiEncoderDemo.encodeCrossChainBridgeData(
            sourceChain, targetChain, token, amount, recipient
        );

        bytes memory expectedData = abi.encodePacked(
            sourceChain, targetChain, token, amount, recipient, "CROSS_CHAIN_BRIDGE"
        );
        assertEq(bridgeData, expectedData);
    }

    function test_createDeFiTransactionId() external {
        string memory txType = "SWAP";
        address user = address(0x1000);
        uint256 timestamp = block.timestamp;
        uint256 nonce = 1;

        bytes32 txId = abiEncoderDemo.createDeFiTransactionId(txType, user, timestamp, nonce);

        bytes memory expectedData = abi.encodePacked(
            txType, user, timestamp, nonce, "DEFI_TX"
        );
        assertEq(txId, keccak256(expectedData));
    }

    function test_encodeStopLossOrder() external {
        address user = address(0x1000);
        address token = address(0x2000);
        uint256 amount = 1 ether;
        uint256 stopPrice = 1000;
        uint256 triggerPrice = 900;

        bytes memory data = abiEncoderDemo.encodeStopLossOrder(
            user, token, amount, stopPrice, triggerPrice
        );

        bytes memory expectedData = abi.encodePacked(
            user, token, amount, stopPrice, triggerPrice, "STOP_LOSS_ORDER"
        );
        assertEq(data, expectedData);
    }

    function test_encodeTakeProfitOrder() external {
        address user = address(0x1000);
        address token = address(0x2000);
        uint256 amount = 1 ether;
        uint256 takeProfitPrice = 2000;

        bytes memory data = abiEncoderDemo.encodeTakeProfitOrder(
            user, token, amount, takeProfitPrice
        );

        bytes memory expectedData = abi.encodePacked(
            user, token, amount, takeProfitPrice, "TAKE_PROFIT_ORDER"
        );
        assertEq(data, expectedData);
    }

    function test_encodeTrailingStopOrder() external {
        address user = address(0x1000);
        address token = address(0x2000);
        uint256 amount = 1 ether;
        uint256 trailingPercent = 5;
        uint256 activationPrice = 1500;

        bytes memory data = abiEncoderDemo.encodeTrailingStopOrder(
            user, token, amount, trailingPercent, activationPrice
        );

        bytes memory expectedData = abi.encodePacked(
            user, token, amount, trailingPercent, activationPrice, "TRAILING_STOP_ORDER"
        );
        assertEq(data, expectedData);
    }

    // --- Added for Research/Benchmark purposes ---

    function test_encodeStandard_ReturnsCorrectEncoding() external view {
        address token = address(0x1234);
        uint256 amount = 1 ether;

        bytes memory data = abiEncoderDemo.encodeStandard(token, amount);
        bytes memory expected = abi.encode(token, amount);

        assertEq(data, expected, "Standard encoding should match abi.encode");
    }

    function test_encodePacked_ReturnsCorrectPackedEncoding() external view {
        address token = address(0x1234);
        uint256 amount = 1 ether;

        bytes memory data = abiEncoderDemo.encodePacked(token, amount);
        bytes memory expected = abi.encodePacked(token, amount);

        assertEq(data, expected, "Packed encoding should match abi.encodePacked");
    }
}