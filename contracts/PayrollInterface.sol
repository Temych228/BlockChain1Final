// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title PayrollInterface
 * @dev Интерфейс для Payroll с поддержкой кампаний и mintable токенов.
 */
interface PayrollInterface {

    /* --- OWNER ONLY --- */

    function allowToken(address _employeeAddress, address _token, uint256 _exchangeRate) external;
    
    // exchangeRate = tokens per 1 EUR, mintable flag indicates whether token supports mint()
    function addSupportedToken(address _token, uint256 _exchangeRate, bool _mintable) external;
    
    function claimTokenFunds(address _tokenAddress) external;
    
    function calculatePayrollBurnrate() external view returns (uint256); // Ежемесячные затраты в EUR
    
    function calculatePayrollRunway(address _token) external view returns (uint256); // Запас средств в днях
    
    function blockPayments() external;
    
    function allowPayments() external;
    
    function setOracle(address _newOracleAddress) external;
    
    function destroy() external;

    function addEmployee(address _employeeAddress, uint256 _initialYearlyEURSalary) external;
    
    function getEmployee(address _employeeAddress) external view returns (
        uint256 yearlyEURSalary,
        uint256 totalReceivedEUR,
        address[] memory allowedTokens
    );
    
    function removeEmployee(address _employeeAddress) external;
    
    function setEmployeeSalary(address _employeeAddress, uint256 _yearlyEURSalary) external;
    
    function getEmployeeCount() external view returns (uint256);
    
    function getEmployeePayment(address _employeeAddress, address _token) external view returns (
        uint256 exchangeRate,
        uint256 lastAllocationTime,
        uint256 lastPaymentTime,
        uint256 monthlyTokenAmount
    );

    /* --- EMPLOYEE ONLY --- */

    function determineAllocation(address _token, uint256 _monthlyAmount) external; 
    
    function payday(address _token) external; 

    /* --- ORACLE ONLY --- */

    function setExchangeRate(address _token, uint256 _newExchangeRate) external;

    /* --- CAMPAIGN / CROWDFUNDING --- */

    function createCampaign(string calldata _title, uint256 _goalEUR, uint256 _durationSeconds, address _rewardToken) external;
    function contributeToCampaign(uint256 _campaignId) external payable;
    function finalizeCampaign(uint256 _campaignId) external;
    function getCampaignInfo(uint256 _campaignId) external view returns (
        string memory title,
        uint256 goalEUR,
        uint256 raisedEUR,
        uint256 deadline,
        bool finalized,
        address rewardToken
    );
}