const EquityToken = artifacts.require("EquityToken");
const TransferValidator = artifacts.require("TransferValidator");
const MockUSDTToken = artifacts.require("MockUSDTToken");

module.exports = async (deployer) => {
    await deployer.deploy(TransferValidator);
    await deployer.deploy(MockUSDTToken);
    await deployer.deploy(EquityToken, "EquityToken", "ET", TransferValidator.address, MockUSDTToken.address);
};