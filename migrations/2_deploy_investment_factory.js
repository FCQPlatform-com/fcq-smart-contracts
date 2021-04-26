const InvestmentFactory = artifacts.require("InvestmentFactory");

module.exports = async (deployer, network, accounts) => {
    // accounts[0] - deployer/owner
    // accounts[1] - platform
    // accounts[2] - operator
    await deployer.deploy(InvestmentFactory, accounts[1], accounts[2]);
};