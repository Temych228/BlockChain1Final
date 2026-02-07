// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title PrisonFund
 * @dev Crowdfunding фонд для финансирования зарплат заключённых.
 * Средства аккумулируются и передаются в Payroll.
 */
contract PrisonFund {
    address public owner;
    address public payroll;

    uint256 public totalRaised;

    mapping(address => uint256) public contributions;

    event ContributionReceived(address indexed contributor, uint256 amount);
    event FundsTransferredToPayroll(uint256 amount);
    event PayrollAddressUpdated(address indexed newPayroll);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address _payroll) {
        require(_payroll != address(0), "Invalid payroll address");
        owner = msg.sender;
        payroll = _payroll;
    }

    /// @notice Пожертвование в фонд
    function contribute() public payable {
        require(msg.value > 0, "Zero contribution");

        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;

        emit ContributionReceived(msg.sender, msg.value);
    }

    /// @notice Перевод средств в Payroll
    function transferToPayroll(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Zero amount");
        require(address(this).balance >= _amount, "Insufficient balance");

        (bool success, ) = payroll.call{value: _amount}("");
        require(success, "Transfer failed");

        emit FundsTransferredToPayroll(_amount);
    }

    /// @notice Обновление адреса Payroll
    function setPayroll(address _newPayroll) external onlyOwner {
        require(_newPayroll != address(0), "Invalid payroll");
        payroll = _newPayroll;
        emit PayrollAddressUpdated(_newPayroll);
    }

    /// @notice Баланс фонда
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {
        contribute();
    }
}
