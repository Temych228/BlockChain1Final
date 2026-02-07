// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./PayrollInterface.sol";

/**
 * @title Payroll
 * @dev System for managing inmate salaries and multi-token distributions and simple crowdfunding.
 *
 *  - сохраняет оригинальную минимальную функциональность (addEmployee, payday, allowToken и т.д.)
 *  - добавляет поддержку mintable токенов (через IMintable)
 *  - добавляет Campaigns (create, contribute, finalize, refund helpers)
 *  - добавляет приём ETH (receive) и учёт ethReserve
 *  - сохраняет модификаторы/роли Owner / Oracle / Employee
 */

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract Payroll is PayrollInterface {
    /* ---------------------------
       STRUCTS & STATE
       --------------------------- */

    struct Token {
        address id;
        uint256 exchangeRate; // Number of tokens per 1 EUR
        bool mintable;
    }

    struct Employee {
        address id;
        uint256 yearlyEURSalary;
        uint256 totalReceivedEUR;
        address[] allowedTokens;
        mapping(address => bool) isTokenAllowed;
        mapping(address => uint256) lastAllocationTime;
        mapping(address => uint256) lastPaymentTime;
        mapping(address => uint256) distributionMonthlyAmount; // In EUR
    }

    enum State {
        Allowed,
        Blocked
    }

    State public paymentsState;
    address public owner;
    address public oracle;
    uint256 public employeeCount;
    uint256 private totalYearlyEURSalary;

    mapping(address => Token) public supportedTokens;
    mapping(address => Employee) private employees;
    address[] private employeeAddresses;

    // --- Campaigns ---
    struct Campaign {
        string title;
        uint256 goalEUR;
        uint256 raisedEUR;
        uint256 deadline;
        bool finalized;
        address rewardToken; // must be in supportedTokens
        address[] contributors;
        mapping(address => uint256) contributionsEUR; // EUR-equivalent contributions per contributor
        uint256 totalEthWei; // total raw ETH wei contributed (keeps contract's ETH accounting)
    }

    mapping(uint256 => Campaign) private campaigns;
    uint256 private campaignCount;

    // ETH -> EUR conversion multiplier (18 decimals). eurAmount = msg.value * ethToEurRate / 1e18
    uint256 public ethToEurRate;

    // ETH reserve received (from PrisonFund or direct transfers)
    uint256 public ethReserveWei;

    /* ---------------------------
       EVENTS
       --------------------------- */

    event EmployeeAdded(address indexed employee, uint256 salary);
    event PaymentMade(address indexed employee, address token, uint256 amount);
    event AllocationChanged(
        address indexed employee,
        address token,
        uint256 amount
    );

    event TokenSupported(
        address indexed token,
        uint256 exchangeRate,
        bool mintable
    );
    event EthReceived(address indexed from, uint256 amountWei);
    event CampaignCreated(
        uint256 indexed campaignId,
        string title,
        uint256 goalEUR,
        uint256 deadline,
        address rewardToken
    );
    event CampaignContribution(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 eurAmount,
        uint256 weiAmount
    );
    event CampaignFinalized(uint256 indexed campaignId, bool success);
    event CampaignRefunded(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 weiAmount
    );
    event EthWithdrawn(address indexed to, uint256 amountWei);

    /* ---------------------------
       CONSTRUCTOR
       --------------------------- */

    constructor(
        address _defaultOracle,
        address _tokenEURAddress,
        uint256 _EURExchangeRate,
        uint256 _ethToEurRate
    ) {
        require(_defaultOracle != address(0), "Invalid oracle");
        owner = msg.sender;
        oracle = _defaultOracle;
        paymentsState = State.Allowed;

        ethToEurRate = _ethToEurRate;

        // default add EUR token (may be mintable depending on token contract ownership)
        supportedTokens[_tokenEURAddress] = Token(
            _tokenEURAddress,
            _EURExchangeRate,
            true
        );
        emit TokenSupported(_tokenEURAddress, _EURExchangeRate, true);
    }

    /* ---------------------------
       MODIFIERS
       --------------------------- */

    modifier onlyByOwner() {
        require(msg.sender == owner, "Only Admin");
        _;
    }

    modifier onlyByOracle() {
        require(msg.sender == oracle, "Only Oracle");
        _;
    }

    modifier onlyByEmployee() {
        require(
            employees[msg.sender].id != address(0),
            "Not a registered worker"
        );
        _;
    }

    modifier whenAllowed() {
        require(paymentsState == State.Allowed, "Payments are frozen");
        _;
    }

    /* ---------------------------
       OWNER FUNCTIONS (existing)
       --------------------------- */

    function addEmployee(
        address _employeeAddress,
        uint256 _initialYearlyEURSalary
    ) external override onlyByOwner {
        require(_employeeAddress != address(0), "Invalid address");
        require(employees[_employeeAddress].id == address(0), "Already exists");

        Employee storage emp = employees[_employeeAddress];
        emp.id = _employeeAddress;
        emp.yearlyEURSalary = _initialYearlyEURSalary;

        employeeAddresses.push(_employeeAddress);
        employeeCount++;
        totalYearlyEURSalary += _initialYearlyEURSalary;

        emit EmployeeAdded(_employeeAddress, _initialYearlyEURSalary);
    }

    function allowToken(
        address _employeeAddress,
        address _token,
        uint256 /*_exchangeRate*/
    ) external override onlyByOwner {
        require(_employeeAddress != address(0), "Invalid employee");
        require(
            supportedTokens[_token].id != address(0),
            "Token not supported"
        );
        Employee storage emp = employees[_employeeAddress];
        require(emp.id != address(0), "Employee not registered");
        require(!emp.isTokenAllowed[_token], "Already allowed");

        emp.isTokenAllowed[_token] = true;
        emp.allowedTokens.push(_token);
    }

    function addSupportedToken(
        address _token,
        uint256 _exchangeRate,
        bool _mintable
    ) public override onlyByOwner {
        require(_token != address(0), "Invalid token");
        require(_exchangeRate > 0, "Invalid rate");
        supportedTokens[_token] = Token(_token, _exchangeRate, _mintable);
        emit TokenSupported(_token, _exchangeRate, _mintable);
    }

    function setEmployeeSalary(
        address _employeeAddress,
        uint256 _yearlyEURSalary
    ) external override onlyByOwner {
        require(
            employees[_employeeAddress].id != address(0),
            "Employee not exists"
        );
        totalYearlyEURSalary =
            totalYearlyEURSalary -
            employees[_employeeAddress].yearlyEURSalary +
            _yearlyEURSalary;
        employees[_employeeAddress].yearlyEURSalary = _yearlyEURSalary;
    }

    function blockPayments() external override onlyByOwner {
        paymentsState = State.Blocked;
    }
    function allowPayments() external override onlyByOwner {
        paymentsState = State.Allowed;
    }
    function setOracle(
        address _newOracleAddress
    ) external override onlyByOwner {
        require(_newOracleAddress != address(0), "Invalid");
        oracle = _newOracleAddress;
    }

    /* ---------------------------
       EMPLOYEE FUNCTIONS (existing)
       --------------------------- */

    function determineAllocation(
        address _token,
        uint256 _monthlyAmountEUR
    ) external override onlyByEmployee whenAllowed {
        Employee storage emp = employees[msg.sender];
        require(emp.isTokenAllowed[_token], "Token not allowed for you");
        require(
            block.timestamp >= emp.lastAllocationTime[_token] + 26 weeks,
            "Can change only every 6 months"
        );

        uint256 monthlyTotalSalary = emp.yearlyEURSalary / 12;
        require(
            _monthlyAmountEUR <= monthlyTotalSalary,
            "Exceeds monthly salary"
        );

        emp.distributionMonthlyAmount[_token] = _monthlyAmountEUR;
        emp.lastAllocationTime[_token] = block.timestamp;

        emit AllocationChanged(msg.sender, _token, _monthlyAmountEUR);
    }

    /// @notice Employee requests monthly payout in a specified token
    function payday(
        address _token
    ) external override onlyByEmployee whenAllowed {
        Employee storage emp = employees[msg.sender];
        if (emp.lastPaymentTime[_token] != 0) {
            require(
                block.timestamp >= emp.lastPaymentTime[_token] + 4 weeks,
                "Monthly limit not reached"
            );
        }

        uint256 amountEUR = emp.distributionMonthlyAmount[_token];
        require(amountEUR > 0, "No allocation for this token");

        uint256 tokenAmount = amountEUR * supportedTokens[_token].exchangeRate;

        emp.lastPaymentTime[_token] = block.timestamp;
        emp.totalReceivedEUR += amountEUR;

        Token memory t = supportedTokens[_token];

        if (t.mintable) {
            // Mint if token contract supports mint and Payroll is owner/minter
            IMintable(t.id).mint(msg.sender, tokenAmount);
        } else {
            // Transfer from Payroll balance; Payroll must be pre-funded with tokens
            require(
                IERC20(t.id).transfer(msg.sender, tokenAmount),
                "Insufficient token balance in contract"
            );
        }

        emit PaymentMade(msg.sender, _token, tokenAmount);
    }

    /* ---------------------------
       ORACLE FUNCTIONS
       --------------------------- */

    function setExchangeRate(
        address _token,
        uint256 _newRate
    ) external override onlyByOracle {
        require(
            supportedTokens[_token].id != address(0),
            "Token not supported"
        );
        require(_newRate > 0, "Rate must be >0");
        supportedTokens[_token].exchangeRate = _newRate;
    }

    function setEthToEurRate(uint256 _newRate) external onlyByOracle {
        require(_newRate > 0, "Invalid rate");
        ethToEurRate = _newRate;
    }

    /* ---------------------------
       VIEW HELPERS
       --------------------------- */

    function calculatePayrollBurnrate()
        external
        view
        override
        returns (uint256)
    {
        return totalYearlyEURSalary / 12;
    }

    function calculatePayrollRunway(
        address _token
    ) external view override returns (uint256) {
        Token memory t = supportedTokens[_token];
        if (t.mintable) {
            return type(uint256).max; // infinite (mintable)
        } else {
            uint256 balance = IERC20(t.id).balanceOf(address(this));
            uint256 monthlyNeed = (totalYearlyEURSalary / 12) * t.exchangeRate;
            if (monthlyNeed == 0) return 9999;
            return (balance / monthlyNeed) * 30;
        }
    }

    function getEmployee(
        address _addr
    ) external view override returns (uint256, uint256, address[] memory) {
        Employee storage e = employees[_addr];
        return (e.yearlyEURSalary, e.totalReceivedEUR, e.allowedTokens);
    }

    function getEmployeeCount() external view override returns (uint256) {
        return employeeCount;
    }

    function getEmployeePayment(
        address _e,
        address _t
    ) external view override returns (uint256, uint256, uint256, uint256) {
        return (
            supportedTokens[_t].exchangeRate,
            employees[_e].lastAllocationTime[_t],
            employees[_e].lastPaymentTime[_t],
            employees[_e].distributionMonthlyAmount[_t]
        );
    }

    /* ---------------------------
       CLEANUP
       --------------------------- */

    function removeEmployee(
        address _employeeAddress
    ) external override onlyByOwner {
        require(
            employees[_employeeAddress].id != address(0),
            "Employee does not exist"
        );
        totalYearlyEURSalary -= employees[_employeeAddress].yearlyEURSalary;
        delete employees[_employeeAddress];
        employeeCount--;
    }

    function claimTokenFunds(address _token) external override onlyByOwner {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        require(IERC20(_token).transfer(owner, bal), "Transfer failed");
    }

    function destroy() external override onlyByOwner {
        selfdestruct(payable(owner));
    }

    /* ---------------------------
       ETH SUPPORT (receive / reserve)
       --------------------------- */

    /// @notice Accept ETH (e.g. from PrisonFund). Increments ethReserveWei.
    receive() external payable {
        require(msg.value > 0, "Zero ETH");
        ethReserveWei += msg.value;
        emit EthReceived(msg.sender, msg.value);
    }

    /// @notice Owner may withdraw ETH from reserve to an address (for off-chain conversion or other uses)
    function withdrawEth(
        address payable _to,
        uint256 _amountWei
    ) external onlyByOwner {
        require(_to != address(0), "Invalid to");
        require(_amountWei <= ethReserveWei, "Amount > reserve");
        ethReserveWei -= _amountWei;
        (bool ok, ) = _to.call{value: _amountWei}("");
        require(ok, "ETH transfer failed");
        emit EthWithdrawn(_to, _amountWei);
    }

    /* ---------------------------
       CAMPAIGN / CROWDFUNDING
       --------------------------- */

    /// @notice Create a crowdfunding campaign. Owner only.
    function createCampaign(
        string calldata _title,
        uint256 _goalEUR,
        uint256 _durationSeconds,
        address _rewardToken
    ) external override onlyByOwner {
        require(_durationSeconds > 0, "Duration must be >0");
        require(
            supportedTokens[_rewardToken].id != address(0),
            "Unsupported reward token"
        );
        uint256 id = campaignCount++;
        Campaign storage c = campaigns[id];
        c.title = _title;
        c.goalEUR = _goalEUR;
        c.deadline = block.timestamp + _durationSeconds;
        c.finalized = false;
        c.rewardToken = _rewardToken;
        c.raisedEUR = 0;
        c.totalEthWei = 0;

        emit CampaignCreated(id, _title, _goalEUR, c.deadline, _rewardToken);
    }

    /// @notice Contribute to a campaign by sending ETH. ETH is held by the Payroll contract (adds to ethReserveWei).
    /// Conversion to EUR uses ethToEurRate (settable by oracle). contributor's EUR-equivalent recorded for reward distribution.
    function contributeToCampaign(
        uint256 _campaignId
    ) external payable override {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(msg.value > 0, "Send ETH");
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp <= c.deadline, "Campaign ended");
        require(ethToEurRate > 0, "ETH->EUR rate not set");

        // convert wei to EUR-equivalent (with 18 decimals scaling)
        uint256 eurAmount = (msg.value * ethToEurRate) / 1e18;
        require(eurAmount > 0, "Contribution too small (EUR equiv 0)");

        // update campaign accounting
        if (c.contributionsEUR[msg.sender] == 0) {
            c.contributors.push(msg.sender);
        }
        c.contributionsEUR[msg.sender] += eurAmount;
        c.raisedEUR += eurAmount;
        c.totalEthWei += msg.value;

        // increase global reserve as well
        ethReserveWei += msg.value;
        emit CampaignContribution(
            _campaignId,
            msg.sender,
            eurAmount,
            msg.value
        );
    }

    /// @notice Finalize campaign: if goal reached -> distribute reward tokens proportionally; if failed -> owner can refund ETH or use reserve.
    function finalizeCampaign(
        uint256 _campaignId
    ) external override onlyByOwner {
        require(_campaignId < campaignCount, "Invalid campaign");
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp > c.deadline, "Campaign still active");
        require(!c.finalized, "Already finalized");

        bool success = (c.raisedEUR >= c.goalEUR);

        Token memory t = supportedTokens[c.rewardToken];

        if (success) {
            // Distribute rewards proportional to EUR contributions.
            uint256 totalRaisedEUR = c.raisedEUR;
            // For each contributor, compute token payout = contribEUR * exchangeRate.
            for (uint256 i = 0; i < c.contributors.length; i++) {
                address contributor = c.contributors[i];
                uint256 contribEUR = c.contributionsEUR[contributor];
                if (contribEUR == 0) continue;

                uint256 tokenAmount = contribEUR * t.exchangeRate;

                if (t.mintable) {
                    IMintable(t.id).mint(contributor, tokenAmount);
                } else {
                    // require Payroll contract to be pre-funded with token balance
                    require(
                        IERC20(t.id).transfer(contributor, tokenAmount),
                        "Token transfer failed"
                    );
                }
            }
        } else {
            // Campaign failed: owner can decide how to handle ETH.
            // We DO NOT auto-refund to avoid storing original wei amounts separately here.
            // Provide utility function for owner to refund individual contributors if required.
            // Keep funds in ethReserve (so owner can refund or repurpose).
        }

        c.finalized = true;
        emit CampaignFinalized(_campaignId, success);
    }

    /// @notice Owner helper: refund a single contributor of a failed campaign (refund in wei).
    /// @dev Only usable after campaign finalized and only if it failed.
    function refundContributor(
        uint256 _campaignId,
        address payable _contributor
    ) external onlyByOwner {
        require(_campaignId < campaignCount, "Invalid campaign");
        Campaign storage c = campaigns[_campaignId];
        require(c.finalized, "Not finalized");
        require(c.raisedEUR < c.goalEUR, "Campaign succeeded; no refunds");
        uint256 contribEUR = c.contributionsEUR[_contributor];
        require(contribEUR > 0, "No contribution for address");

        // compute contributor's share of wei: contribWei = contribEUR * totalEthWei / raisedEUR
        if (c.totalEthWei == 0 || c.raisedEUR == 0) revert("No ETH to refund");
        uint256 contribWei = (contribEUR * c.totalEthWei) / c.raisedEUR;
        require(contribWei > 0, "Refund amount zero");
        require(contribWei <= ethReserveWei, "Not enough reserve");

        // zero out mapping and reduce reserve
        c.contributionsEUR[_contributor] = 0;
        ethReserveWei -= contribWei;

        (bool ok, ) = _contributor.call{value: contribWei}("");
        require(ok, "Refund failed");

        emit CampaignRefunded(_campaignId, _contributor, contribWei);
    }

    /// @notice View campaign basic info
    function getCampaignInfo(
        uint256 _campaignId
    )
        external
        view
        override
        returns (
            string memory title,
            uint256 goalEUR,
            uint256 raisedEUR,
            uint256 deadline,
            bool finalized,
            address rewardToken
        )
    {
        require(_campaignId < campaignCount, "Invalid campaign");
        Campaign storage c = campaigns[_campaignId];
        return (
            c.title,
            c.goalEUR,
            c.raisedEUR,
            c.deadline,
            c.finalized,
            c.rewardToken
        );
    }

    /// @notice Helper: get contributors list for a campaign (may be large; for small test cases it's OK)
    function getCampaignContributors(
        uint256 _campaignId
    ) external view returns (address[] memory) {
        require(_campaignId < campaignCount, "Invalid campaign");
        return campaigns[_campaignId].contributors;
    }

    /* ---------------------------
       FALLBACK / UTIL
       --------------------------- */

    fallback() external payable {
        // Accept ETH via fallback as well (counts toward ethReserve)
        if (msg.value > 0) {
            ethReserveWei += msg.value;
            emit EthReceived(msg.sender, msg.value);
        }
    }
}
