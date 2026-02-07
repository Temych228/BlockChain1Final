const { ethers } = require("hardhat");

async function main() {
  // 1. Получаем аккаунты
  const [admin, oracle, employee1] = await ethers.getSigners();
  console.log("--- Начало развертывания ---");
  console.log("Админ (Owner):", admin.address);
  console.log("Оракул:", oracle.address);

  // Константы
  // Константы
  const INITIAL_SUPPLY = 1_000_000;
  const EUR_RATE = 1;
  const USD_RATE = 2;

  // ETH → EUR (18 decimals)
  const ETH_TO_EUR_RATE = ethers.parseUnits("1800", 18);

  // 2. Развертывание токена EUR (базовый)
  const EURToken = await ethers.getContractFactory("EURToken");
  const eurt = await EURToken.deploy(INITIAL_SUPPLY);
  await eurt.waitForDeployment();
  const eurtAddr = await eurt.getAddress();
  console.log(`EURToken развернут: ${eurtAddr}`);

  // 3. Развертывание токена USD
  const USDToken = await ethers.getContractFactory("USDToken");
  const usdt = await USDToken.deploy(INITIAL_SUPPLY);
  await usdt.waitForDeployment();
  const usdtAddr = await usdt.getAddress();
  console.log(`USDToken развернут: ${usdtAddr}`);

  // 4. Развертывание Payroll

  const Payroll = await ethers.getContractFactory("Payroll");
  const payroll = await Payroll.deploy(
    oracle.address,
    eurtAddr,
    EUR_RATE,
    ETH_TO_EUR_RATE
  );
  await payroll.waitForDeployment();
  const payrollAddr = await payroll.getAddress();
  console.log(`Payroll развернут: ${payrollAddr}`);

  // 5. 🔥 Развертывание PrisonFund (crowdfunding)
  const PrisonFund = await ethers.getContractFactory("PrisonFund");
  const prisonFund = await PrisonFund.deploy(payrollAddr);
  await prisonFund.waitForDeployment();
  const prisonFundAddr = await prisonFund.getAddress();
  console.log(`PrisonFund развернут: ${prisonFundAddr}`);

  // --- Настройка системы после деплоя ---
  console.log("\n--- Первичная настройка ---");

  // Добавляем USDT как поддерживаемый токен
  await payroll.addSupportedToken(usdtAddr, USD_RATE, false);
  console.log("USDT добавлен в список поддерживаемых валют.");

  // Пополняем Payroll токенами для выплат
  const fundingAmount = ethers.parseEther("10000"); // 10,000 токенов
  await eurt.transfer(payrollAddr, fundingAmount);
  await usdt.transfer(payrollAddr, fundingAmount);
  console.log("Payroll пополнен токенами для зарплат.");

  // Тестовая регистрация сотрудника
  const yearlySalary = 12000; // 12,000 EUR в год
  await payroll.addEmployee(employee1.address, yearlySalary);
  await payroll.allowToken(employee1.address, eurtAddr, EUR_RATE);
  console.log(`Сотрудник ${employee1.address} зарегистрирован.`);

  console.log("\n--- Готово! Данные для фронтенда: ---");
  console.log({
    payroll: payrollAddr,
    prisonFund: prisonFundAddr,
    eurToken: eurtAddr,
    usdToken: usdtAddr,
    oracle: oracle.address,
    owner: admin.address
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
