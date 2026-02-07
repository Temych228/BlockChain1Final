// App.js
import React, { useState, useEffect, useCallback } from "react";
import { ethers } from "ethers";

/*
  ------- CONFIG (replace the placeholders with your deployed addresses) -------
  After running your deploy script (deploy_all.js) copy the printed addresses here.
*/
const PAYROLL_ADDRESS = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"; // <--- REPLACE with payroll contract address
const EUR_TOKEN_ADDR = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // <--- REPLACE with EUR token address
const HARDHAT_CHAIN_ID = "0x7a69"; // hex for 31337

// Minimal Payroll ABI (string fragments acceptable for ethers)
const PAYROLL_ABI = [
  "function owner() view returns (address)",
  "function oracle() view returns (address)",
  "function addEmployee(address _employeeAddress, uint256 _initialYearlyEURSalary) external",
  "function allowToken(address _employeeAddress, address _token, uint256 _exchangeRate) external",
  "function addSupportedToken(address _token, uint256 _exchangeRate, bool _mintable) external",
  "function setExchangeRate(address _token, uint256 _newRate) external",
  "function getEmployee(address _addr) view returns (uint256 salary, uint256 received, address[] tokens)",
  "function payday(address _token) external",
  "function calculatePayrollRunway(address _token) view returns (uint256)",
  "function calculatePayrollBurnrate() view returns (uint256)"
];

function App() {
  // wallet + roles
  const [account, setAccount] = useState(null);
  const [isOwner, setIsOwner] = useState(false);
  const [isOracle, setIsOracle] = useState(false);
  const [isAdminView, setIsAdminView] = useState(false);

  // UI data
  const [employeeData, setEmployeeData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [errorBanner, setErrorBanner] = useState("");

  // forms
  const [newEmp, setNewEmp] = useState({ addr: "", salary: "" });
  const [rateUpdate, setRateUpdate] = useState({ token: EUR_TOKEN_ADDR, rate: "" });

  // ----------------------
  // Helper utilities
  // ----------------------
  const short = (addr = "") => (addr && addr.length > 10 ? `${addr.substring(0, 6)}...${addr.slice(-4)}` : addr);

  const safeToString = (v) => {
    try {
      // BigInt or ethers BigNumber -> toString
      return v?.toString?.() ?? String(v ?? "");
    } catch {
      return String(v ?? "");
    }
  };

  // ----------------------
  // Network / MetaMask checks
  // ----------------------
  const checkNetwork = useCallback(async () => {
    if (!window.ethereum) {
      setErrorBanner("MetaMask not found in the browser.");
      return false;
    }
    try {
      const chainId = await window.ethereum.request({ method: "eth_chainId" });
      if (chainId !== HARDHAT_CHAIN_ID) {
        setErrorBanner("Please switch MetaMask to the local Hardhat network (chainId 31337).");
        return false;
      }
      setErrorBanner("");
      return true;
    } catch (err) {
      console.error("Network check failed:", err);
      setErrorBanner("Failed to detect chainId.");
      return false;
    }
  }, []);

  // ----------------------
  // Fetch roles & employee data
  // ----------------------
  const fetchRolesAndData = useCallback(
    async (userAddr) => {
      if (!userAddr) return;
      try {
        const provider = new ethers.BrowserProvider(window.ethereum);
        const contract = new ethers.Contract(PAYROLL_ADDRESS, PAYROLL_ABI, provider);

        // fetch owner, oracle, employee (do in parallel)
        const [ownerAddr, oracleAddr, empInfo] = await Promise.all([
          contract.owner().catch(() => null),
          contract.oracle().catch(() => null),
          contract.getEmployee(userAddr).catch(() => null)
        ]);

        if (ownerAddr) setIsOwner(ownerAddr.toLowerCase() === userAddr.toLowerCase());
        else setIsOwner(false);

        if (oracleAddr) setIsOracle(oracleAddr.toLowerCase() === userAddr.toLowerCase());
        else setIsOracle(false);

        // empInfo could be null if not registered
        if (empInfo) {
          // empInfo: [salary, received, tokens[]]
          const salary = safeToString(empInfo[0]);
          const received = safeToString(empInfo[1]);
          const tokens = Array.isArray(empInfo[2]) ? empInfo[2] : [];
          setEmployeeData({
            salary,
            received,
            tokens
          });
        } else {
          setEmployeeData(null);
        }
      } catch (err) {
        console.error("Error fetching roles/employee data:", err);
      }
    },
    []
  );

  // ----------------------
  // Wallet connect
  // ----------------------
  const connectWallet = async () => {
    if (!window.ethereum) {
      alert("MetaMask not found. Please install MetaMask and try again.");
      return;
    }
    try {
      // request accounts via window.ethereum.request (recommended)
      const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
      const user = accounts[0];
      setAccount(user);

      // ensure network is correct (chainId)
      const chainId = await window.ethereum.request({ method: "eth_chainId" });
      if (chainId !== HARDHAT_CHAIN_ID) {
        alert("Please switch MetaMask to the Hardhat local network (chainId 31337).");
        return;
      }

      // immediately fetch roles + employee data
      await fetchRolesAndData(user);
      console.log("Connected account:", user);
    } catch (err) {
      console.error("Failed to connect wallet:", err);
      alert("Failed to connect wallet: " + (err?.message || err));
    }
  };

  // ----------------------
  // React lifecycle: account / chain changes
  // ----------------------
  useEffect(() => {
    if (!window.ethereum) return;
    const handleAccounts = (accs) => {
      const a = Array.isArray(accs) ? accs[0] : accs;
      setAccount(a);
      if (a) fetchRolesAndData(a);
      else {
        setEmployeeData(null);
        setIsOwner(false);
        setIsOracle(false);
      }
    };
    const handleChain = (chainId) => {
      // simple reload to reset state and re-check network
      // (this behavior matches many dapps)
      window.location.reload();
    };

    window.ethereum.on && window.ethereum.on("accountsChanged", handleAccounts);
    window.ethereum.on && window.ethereum.on("chainChanged", handleChain);

    // initial check of network (banner)
    checkNetwork();

    return () => {
      if (window.ethereum && window.ethereum.removeListener) {
        window.ethereum.removeListener("accountsChanged", handleAccounts);
        window.ethereum.removeListener("chainChanged", handleChain);
      }
    };
  }, [checkNetwork, fetchRolesAndData]);

  // Also refresh roles whenever account state changes (safe-guard)
  useEffect(() => {
    if (account) fetchRolesAndData(account);
  }, [account, fetchRolesAndData]);

  // ----------------------
  // Admin actions
  // ----------------------
  const registerEmployee = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      // get signer
      const provider = new ethers.BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(PAYROLL_ADDRESS, PAYROLL_ABI, signer);

      // addEmployee expects uint256 salary; make sure to send number
      const tx = await contract.addEmployee(newEmp.addr, ethers.toBigInt(String(newEmp.salary)));
      await tx.wait();
      alert("Employee registered successfully.");
      // refresh
      await fetchRolesAndData(account);
    } catch (err) {
      console.error("registerEmployee error:", err);
      alert("Error registering employee: " + (err?.reason || err?.message || "Transaction failed"));
    } finally {
      setLoading(false);
    }
  };

  const updateRate = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      const provider = new ethers.BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(PAYROLL_ADDRESS, PAYROLL_ABI, signer);

      const tx = await contract.setExchangeRate(rateUpdate.token, ethers.toBigInt(String(rateUpdate.rate)));
      await tx.wait();
      alert("Exchange rate updated by oracle.");
      await fetchRolesAndData(account);
    } catch (err) {
      console.error("updateRate error:", err);
      alert("Error updating rate: " + (err?.reason || err?.message || "Only oracle can set rates"));
    } finally {
      setLoading(false);
    }
  };

  // ----------------------
  // Employee actions
  // ----------------------
  const handlePayday = async (tokenAddr) => {
    setLoading(true);
    try {
      const provider = new ethers.BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(PAYROLL_ADDRESS, PAYROLL_ABI, signer);

      const tx = await contract.payday(tokenAddr);
      await tx.wait();
      alert("Payment successful — tokens should be delivered.");
      // refresh balances / employee data
      await fetchRolesAndData(account);
    } catch (err) {
      console.error("handlePayday error:", err);
      // give a helpful fallback message
      const errMsg = err?.reason || err?.message || "Payment failed. You may only request payout once per 4 weeks or token allocation is missing.";
      alert("Error: " + errMsg);
    } finally {
      setLoading(false);
    }
  };

  // ----------------------
  // Render
  // ----------------------
  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1>Correctional Work Payroll</h1>
        {errorBanner && <div style={styles.errorBanner}>{errorBanner}</div>}
        {!account ? (
          <button onClick={connectWallet} style={styles.connectBtn}>
            Connect Wallet
          </button>
        ) : (
          <div style={styles.userBadge}>
            👤 {short(account)}
            {isOwner && <span title="Admin"> 🛡️</span>}
            {isOracle && <span title="Oracle"> 🔮</span>}
          </div>
        )}
      </header>

      {account && (
        <>
          <div style={styles.tabs}>
            <button onClick={() => setIsAdminView(false)} style={!isAdminView ? styles.activeTab : styles.tab}>
              Dashboard
            </button>
            <button onClick={() => setIsAdminView(true)} style={isAdminView ? styles.activeTab : styles.tab}>
              Admin Panel
            </button>
          </div>

          <main style={styles.main}>
            {isAdminView ? (
              <div style={styles.adminGrid}>
                <div style={styles.card}>
                  <h3>Register Employee</h3>
                  <form onSubmit={registerEmployee}>
                    <input
                      style={styles.input}
                      placeholder="Employee address (0x...)"
                      value={newEmp.addr}
                      onChange={(e) => setNewEmp({ ...newEmp, addr: e.target.value })}
                    />
                    <input
                      style={styles.input}
                      type="number"
                      placeholder="Yearly salary (EUR)"
                      value={newEmp.salary}
                      onChange={(e) => setNewEmp({ ...newEmp, salary: e.target.value })}
                    />
                    <button type="submit" style={styles.adminBtn} disabled={!isOwner || loading}>
                      Register Employee
                    </button>
                  </form>
                </div>

                <div style={styles.card}>
                  <h3>Update Exchange Rate (Oracle)</h3>
                  <form onSubmit={updateRate}>
                    <input
                      style={styles.input}
                      placeholder="Token address"
                      value={rateUpdate.token}
                      onChange={(e) => setRateUpdate({ ...rateUpdate, token: e.target.value })}
                    />
                    <input
                      style={styles.input}
                      type="number"
                      placeholder="Tokens per 1 EUR"
                      value={rateUpdate.rate}
                      onChange={(e) => setRateUpdate({ ...rateUpdate, rate: e.target.value })}
                    />
                    <button type="submit" style={{ ...styles.adminBtn, background: "#f39c12" }} disabled={!isOracle || loading}>
                      Update Rate
                    </button>
                  </form>
                </div>
              </div>
            ) : (
              <div style={styles.card}>
                {employeeData ? (
                  <>
                    <h3>Your Work Profile</h3>
                    <div style={styles.stats}>
                      <p>
                        Yearly salary: <strong>{employeeData.salary} EUR</strong>
                      </p>
                      <p>
                        Already received: <strong>{employeeData.received} EUR</strong>
                      </p>
                    </div>
                    <hr />
                    <h4>Available payouts</h4>

                    {Array.isArray(employeeData.tokens) && employeeData.tokens.length > 0 ? (
                      employeeData.tokens.map((t) => (
                        <button key={t} onClick={() => handlePayday(t)} style={styles.payBtn} disabled={loading}>
                          {loading ? "Loading..." : `Claim payout in ${short(t)}`}
                        </button>
                      ))
                    ) : (
                      <p>Payment tokens are not assigned by the administrator.</p>
                    )}
                  </>
                ) : (
                  <p>You are not registered as an employee. Please contact the owner/admin.</p>
                )}
              </div>
            )}
          </main>
        </>
      )}
    </div>
  );
}

// inline styles (kept similar to your original)
const styles = {
  container: { maxWidth: "900px", margin: "0 auto", padding: "20px", fontFamily: "system-ui" },
  header: { borderBottom: "2px solid #222", paddingBottom: "18px", marginBottom: "18px" },
  errorBanner: { background: "#ff4444", color: "#fff", padding: "10px", borderRadius: "6px", margin: "10px 0" },
  userBadge: { background: "#eee", padding: "8px 15px", borderRadius: "20px", display: "inline-block" },
  connectBtn: { padding: "10px 20px", background: "#007bff", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" },
  tabs: { display: "flex", gap: "10px", marginBottom: "16px" },
  tab: { padding: "10px 18px", cursor: "pointer", border: "1px solid #ddd", background: "#f9f9f9", borderRadius: "6px" },
  activeTab: { padding: "10px 18px", cursor: "pointer", border: "1px solid #222", background: "#222", color: "#fff", borderRadius: "6px" },
  main: { background: "#fff", minHeight: "320px", padding: "16px", borderRadius: "8px" },
  adminGrid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: "20px" },
  card: { padding: "18px", border: "1px solid #eee", borderRadius: "10px", boxShadow: "0 6px 10px rgba(0,0,0,0.04)" },
  input: { width: "100%", padding: "10px", marginBottom: "10px", borderRadius: "6px", border: "1px solid #ddd", boxSizing: "border-box" },
  adminBtn: { width: "100%", padding: "10px", background: "#28a745", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer" },
  payBtn: { width: "100%", padding: "14px", background: "#17a2b8", color: "#fff", border: "none", borderRadius: "6px", cursor: "pointer", fontSize: "15px", marginBottom: "8px" },
  stats: { fontSize: "16px", lineHeight: "1.6" }
};

export default App;
