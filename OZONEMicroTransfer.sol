// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title OZONE Micro-Transfer Demo
/// @notice Distributes a deposited native-coin amount in bounded batches.
/// @dev Each processBatch() call is ONE blockchain transaction containing
///      up to MAX_BATCH internal native-coin transfers.
contract OZONEMicroTransfer {
    address public immutable owner;

    uint256 public constant MAX_BATCH = 50;

    address payable public recipient;
    uint256 public paymentAmount;
    uint256 public remaining;
    uint256 public totalDistributed;
    uint256 public totalTransfers;
    bool public active;
    bool private locked;

    event CampaignStarted(
        address indexed recipient,
        uint256 totalAmount,
        uint256 paymentAmount,
        uint256 expectedTransfers
    );

    event MicroTransfer(
        address indexed recipient,
        uint256 amount,
        uint256 transferNumber
    );

    event BatchProcessed(
        uint256 transfersInBatch,
        uint256 amountInBatch,
        uint256 remaining
    );

    event CampaignCompleted(
        address indexed recipient,
        uint256 totalDistributed,
        uint256 totalTransfers
    );

    event CampaignCancelled(uint256 refundedAmount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Start a campaign by depositing the exact amount to distribute.
    /// @param _recipient Wallet that receives each micro-payment.
    /// @param _paymentAmount Amount per internal transfer, in wei.
    function startCampaign(
        address payable _recipient,
        uint256 _paymentAmount
    ) external payable onlyOwner {
        require(!active, "Campaign already active");
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != address(this), "Cannot pay contract");
        require(msg.value > 0, "Deposit required");
        require(_paymentAmount > 0, "Payment must be positive");
        require(_paymentAmount <= msg.value, "Payment exceeds deposit");

        recipient = _recipient;
        paymentAmount = _paymentAmount;
        remaining = msg.value;
        totalDistributed = 0;
        totalTransfers = 0;
        active = true;

        uint256 expectedTransfers =
            (msg.value + _paymentAmount - 1) / _paymentAmount;

        emit CampaignStarted(
            _recipient,
            msg.value,
            _paymentAmount,
            expectedTransfers
        );
    }

    /// @notice Execute up to `count` internal transfers.
    /// @dev Call repeatedly; each call is a separate on-chain transaction.
    function processBatch(uint256 count) external onlyOwner nonReentrant {
        require(active, "No active campaign");
        require(count > 0 && count <= MAX_BATCH, "Batch must be 1..50");

        uint256 batchAmount;
        uint256 batchTransfers;

        while (batchTransfers < count && remaining > 0) {
            uint256 amount = remaining < paymentAmount
                ? remaining
                : paymentAmount;

            // Update state before the external call. A failed call reverts
            // the entire batch, including these state updates.
            remaining -= amount;
            totalDistributed += amount;
            totalTransfers += 1;
            batchAmount += amount;
            batchTransfers += 1;

            (bool success, ) = recipient.call{value: amount}("");
            require(success, "Recipient transfer failed");

            emit MicroTransfer(recipient, amount, totalTransfers);
        }

        emit BatchProcessed(batchTransfers, batchAmount, remaining);

        if (remaining == 0) {
            active = false;
            emit CampaignCompleted(
                recipient,
                totalDistributed,
                totalTransfers
            );
        }
    }

    /// @notice Stop an active campaign and refund the undistributed balance.
    function cancelCampaign() external onlyOwner nonReentrant {
        require(active, "No active campaign");

        uint256 refund = remaining;
        remaining = 0;
        active = false;

        (bool success, ) = payable(owner).call{value: refund}("");
        require(success, "Refund failed");

        emit CampaignCancelled(refund);
    }

    /// @notice Recover any accidental funds when no campaign is active.
    function withdrawUnallocated() external onlyOwner nonReentrant {
        require(!active, "Campaign active");

        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
