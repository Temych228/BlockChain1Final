# Decentralized Payroll DApp

This project is a decentralized payroll application where an administrator manages employee salaries and payments on a local Ethereum network. It uses Solidity smart contracts for payroll logic (including salary management, token payments in EURToken/USDToken, and an ETH crowdfunding fund via PrisonFund) and a React/ethers.js frontend for user interaction. The stack is built with Hardhat (for compiling, testing, and deploying contracts) and OpenZeppelin contracts (e.g. ERC20 tokens). In a typical DApp pattern, Hardhat handles the smart contracts and local blockchain (chainId 31337), while React connects via MetaMask (a user wallet) and ethers.js. The Admin (contract owner) can register employees and update salary rates; registered Employee accounts can view their earned balances and claim payouts in tokens.

Prerequisites

Node.js (v14 or newer; Hardhat 3 recommends Node 22+).

npm or Yarn as a package manager (npm comes with Node; Yarn/pnpm can also be used).

Hardhat (installed via npm install in the project; it provides a local Ethereum network and scripting tools).

MetaMask browser extension (or another Web3 wallet) for interacting with the DApp.

OpenZeppelin Contracts library (installed via npm; provides the ERC20 token implementation).

(Optional) A code editor like VSCode for development.

Installation

Clone the repository and install dependencies in both the root and frontend directories:
git clone <repository-url>
cd <repository-directory>
npm install                    # Installs Hardhat, OpenZeppelin, etc.
cd payroll-frontend
npm install                    # Installs React app dependencies

This sets up the Hardhat project and React frontend. The package.json includes Hardhat and OpenZeppelin contracts; after npm install, you will have the necessary tools (Hardhat runner, ethers.js, etc.) ready.

Deploying Contracts Locally

First, start a Hardhat local node (it simulates an Ethereum testnet at http://127.0.0.1:8545 with chainId 31337). In one terminal, run:
npx hardhat node

You should see output like Started HTTP and WebSocket JSON-RPC server at http://127.0.0.1:8545/ (this runs Hardhat’s local network with 20 funded test accounts).

Next, in a separate terminal window, deploy all contracts using the provided script. With Hardhat running (or you can rely on its in-process network), execute:
npx hardhat run scripts/deploy_all.js --network localhost

This uses Hardhat’s CLI to run your deployment script. (Alternatively, if you didn’t run node above, you can just run npx hardhat run scripts/deploy_all.js and Hardhat will spin up an in-memory network automatically.) After running, the script will output the deployed contract addresses.

Example: Hardhat’s documentation shows deploying with a similar command:
npx hardhat run ./scripts/deploy.js --network localhost.

Minting Tokens

The EURToken and USDToken contracts include a mint function that only the owner (deployer) can call to issue tokens. To mint tokens, use the Hardhat console or write a script. For example, open the Hardhat console connected to your local network:
npx hardhat console --network localhost

Inside the console, you have the ethers object and contract instances available. You can retrieve the deployed token contract and call mint. For example:
const [owner] = await ethers.getSigners();
const eurToken = await ethers.getContract("EURToken");   // Owner has mint role
await eurToken.mint("0xEmployeeAddress", ethers.utils.parseUnits("1000")); 

This mints 1,000 (assuming 18 decimals) EURToken to the given employee address. Repeat similarly for USDToken. (You’ll see the owner address has a large ETH balance by default, so transactions will succeed.) When done, exit the console with Ctrl+C.

Using Hardhat’s console (npx hardhat console) lets you interact with contracts on the local network. It automatically compiles your contracts and gives you ethers and signers in the REPL.

Frontend Setup

The React app in payroll-frontend/ is a typical Create React App project. After installing dependencies (see Installation), start the development server:
cd payroll-frontend
npm start

This runs the app in development mode on http://localhost:3000 . The browser should open automatically (or you can navigate there) and display the DApp’s interface.

Make sure the frontend knows the deployed contract address(es) and network. You might set environment variables (see the Environment Variables section below) so the React code can find the Payroll contract address and the local network RPC URL. Once running, the app will show a “Connect Wallet” or “Connect MetaMask” button. Use this to connect your MetaMask wallet to the app.

In a Create React App project, npm start (or yarn start) launches the development server and opens the app at localhost:3000.

Using the DApp

Connect MetaMask: In MetaMask, select the local Hardhat network (see MetaMask Setup below) and connect your account. Then click the “Connect Wallet” button in the app to authorize.

Admin View (Owner): Use the wallet/address that deployed the contracts (the owner). After connecting, you should see the admin panel. This typically includes forms to register new employees (provide their wallet address) and update salary rates or payment parameters. When you submit these actions, transactions will be sent to the Payroll contract on the local network.

Employee View: Switch MetaMask to a registered employee account (one that the admin added). The app’s dashboard will show that employee’s information: accumulated salary balance, allocated EURToken/USDToken, and any pending payouts. There should be a “Claim” or “Withdraw” button allowing the employee to request their token payment. Clicking it will call the payroll contract’s claim function.

Token Payments: When an employee claims payment, the Payroll contract will distribute the appropriate amount of EURToken and/or USDToken to the employee’s address. You may also need to manually mint tokens (as described above) to ensure the token contracts have supply.

No external citations are needed for this usage section; it describes how the provided UI functions. In general, the admin account drives the payroll logic, while employee accounts see only their own data.

MetaMask Local Network Setup

To work with Hardhat’s local blockchain, configure MetaMask for the localhost network:

Open MetaMask and add a Custom RPC network (or select the existing “Localhost 8545” network if present).

Network Name: e.g. Hardhat Local (any label you like).

New RPC URL: http://127.0.0.1:8545 (Hardhat’s default RPC).

Chain ID: 31337 (Hardhat’s default chain ID).

Currency symbol: ETH (or leave blank).

Save the network. MetaMask will then connect to your local Hardhat node.

Note: Hardhat uses chain ID 31337 by default, whereas MetaMask often assumes 1337 for localhost. Be sure the Chain ID in MetaMask is set to 31337 to match. If you leave it at 1337, you may encounter EIP-155 chain ID errors. (Alternatively, you can change Hardhat’s chainId in hardhat.config.js to 1337, but matching MetaMask to 31337 is simplest.)

For example, Chainstack’s guide shows adding a custom network with RPC 127.0.0.1:8545 and Chain ID 31337. Hardhat’s docs note MetaMask may default to 1337, so manually set 31337.

Once MetaMask is on the Hardhat network, you can switch accounts among the pre-funded Hardhat accounts (they each start with 10000 ETH). Import any of those private keys into MetaMask if needed (they were listed when you ran npx hardhat node) so you can use them in the UI.

Environment Variables

The frontend app can use a .env file (place at payroll-frontend/.env) to store configuration. Create React App requires custom variables to start with REACT_APP_. For example:
# .env (example, do NOT commit secrets)
REACT_APP_HARDHAT_URL=http://127.0.0.1:8545
REACT_APP_CHAIN_ID=31337
REACT_APP_PAYROLL_ADDRESS=0xYourPayrollContractAddressHere
These will be embedded into process.env in the React code. The frontend can then read process.env.REACT_APP_PAYROLL_ADDRESS and connect to the contract on the specified network. After creating or modifying .env, restart npm start to load the new values.

In Create React App, any custom .env variables must begin with REACT_APP_. They will be replaced at build time and accessible in code via process.env.REACT_APP_....

Ensure you replace 0xYourPayrollContractAddressHere with the actual address output by the deployment script. You may also include other variables (e.g. token contract addresses) following the same pattern as needed.
