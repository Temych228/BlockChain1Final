export const PAYROLL_ADDRESS = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";
export const PAYROLL_ABI = [
  "function payday(address token) external",
  "function getEmployee(address addr) view returns (uint256 salary, uint256 received, address[] tokens)",
  "function determineAllocation(address token, uint256 amount) external",
  "function supportedTokens(address) view returns (address id, uint256 rate)",
  "event PaymentMade(address indexed employee, address token, uint256 amount)"
];