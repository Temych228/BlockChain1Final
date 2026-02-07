import React, { useState } from 'react';
import { ethers } from 'ethers';
import { PAYROLL_ADDRESS, PAYROLL_ABI } from './constants';

const AdminPanel = () => {
  // Состояния для формы добавления сотрудника
  const [empAddress, setEmpAddress] = useState('');
  const [yearlySalary, setYearlySalary] = useState('');
  
  // Состояния для оракула
  const [tokenAddress, setTokenAddress] = useState('');
  const [newRate, setNewRate] = useState('');

  const getContract = async (useSigner = false) => {
    const provider = new ethers.BrowserProvider(window.ethereum);
    if (useSigner) {
      const signer = await provider.getSigner();
      return new ethers.Contract(PAYROLL_ADDRESS, PAYROLL_ABI, signer);
    }
    return new ethers.Contract(PAYROLL_ADDRESS, PAYROLL_ABI, provider);
  };

  // Регистрация нового заключенного
  const handleAddEmployee = async (e) => {
    e.preventDefault();
    try {
      const contract = await getContract(true);
      const tx = await contract.addEmployee(empAddress, yearlySalary);
      await tx.wait();
      alert(`Заключенный ${empAddress} успешно добавлен в реестр.`);
    } catch (err) {
      console.error(err);
      alert("Ошибка при добавлении: проверьте права доступа или адрес.");
    }
  };

  // Обновление курса (функция Оракула)
  const handleUpdateRate = async (e) => {
    e.preventDefault();
    try {
      const contract = await getContract(true);
      const tx = await contract.setExchangeRate(tokenAddress, newRate);
      await tx.wait();
      alert("Курс валюты успешно обновлен.");
    } catch (err) {
      console.error(err);
      alert("Ошибка: только назначенный Оракул может менять курс.");
    }
  };

  return (
    <div style={{ display: 'flex', gap: '20px', marginTop: '30px' }}>
      {/* Секция Администратора */}
      <div style={cardStyle}>
        <h3>Регистрация заключенного</h3>
        <form onSubmit={handleAddEmployee}>
          <input 
            placeholder="Address (0x...)" 
            value={empAddress} 
            onChange={(e) => setEmpAddress(e.target.value)} 
            style={inputStyle}
          />
          <input 
            placeholder="Годовая зарплата (EUR)" 
            type="number"
            value={yearlySalary} 
            onChange={(e) => setYearlySalary(e.target.value)} 
            style={inputStyle}
          />
          <button type="submit" style={btnStyle}>Добавить в базу</button>
        </form>
      </div>

      {/* Секция Оракула */}
      <div style={cardStyle}>
        <h3>Управление курсом (Oracle)</h3>
        <form onSubmit={handleUpdateRate}>
          <input 
            placeholder="Token Address" 
            value={tokenAddress} 
            onChange={(e) => setTokenAddress(e.target.value)} 
            style={inputStyle}
          />
          <input 
            placeholder="Новый курс (Токенов за 1 EUR)" 
            type="number"
            value={newRate} 
            onChange={(e) => setNewRate(e.target.value)} 
            style={inputStyle}
          />
          <button type="submit" style={{...btnStyle, backgroundColor: '#f39c12'}}>Обновить курс</button>
        </form>
      </div>
    </div>
  );
};

const cardStyle = { border: '1px solid #ddd', padding: '20px', borderRadius: '10px', flex: 1, backgroundColor: '#f9f9f9' };
const inputStyle = { display: 'block', width: '100%', marginBottom: '10px', padding: '8px', boxSizing: 'border-box' };
const btnStyle = { width: '100%', padding: '10px', backgroundColor: '#27ae60', color: 'white', border: 'none', cursor: 'pointer', borderRadius: '5px' };

export default AdminPanel;