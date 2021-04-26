const truffleAssert = require('truffle-assertions');
const helpers = require('truffle-test-helpers');
const InvestmentFactory = artifacts.require("InvestmentFactory");
const Marketplace = artifacts.require("Marketplace");
const EquityToken = artifacts.require("EquityToken");
const FCQToken = artifacts.require("FCQToken");
const USDTToken = artifacts.require("MockUSDTToken");
const TransferValidator = artifacts.require("./TransferValidator.sol");

contract("Marketplace", async accounts => {
    let owner = accounts[0];
    let platform = accounts[1];
    let operator = accounts[2];
    let buyer = accounts[3];
    let seller = accounts[4];
    let wallet = accounts[5];

    before(async function() {
        // Advance to the next block to correctly read time in the solidity "timestamp" function interpreted by ganache
        await helpers.advanceBlock();
    });

    beforeEach(async function () {
        investmentFactory = await InvestmentFactory.deployed();
        let roles = await investmentFactory.roles();
        token = await EquityToken.deployed();
        usdtToken = await USDTToken.new();
        fcqToken = await FCQToken.new();
        marketplace = await Marketplace.new(100, wallet, [token.address], [usdtToken.address, fcqToken.address], roles);
        // set token issuer 
        await token.setIssuer(owner, { from: owner });
        // fill buyer wallet with USDT tokens
        await usdtToken.transfer(buyer, 100000e6, { from: owner });
        // fill seller wallet with Equity token
        await token.issue(seller, 10, '0x', { from: owner });
        // add marketplace as a authority for equity token, to be able to trnasfer tokens
        transferValidator = await TransferValidator.deployed();
        await transferValidator.addTokenAuthority(token.address, marketplace.address, { from: owner })
    });

    describe("Marketplace creation:", function() {
        it("should create investment", async () => {
            assert.equal(await marketplace.feeWallet(), wallet);
            assert.equal(await marketplace.feeRate(), 100);
            assert.isTrue(await marketplace.isEquityToken(token.address));
            assert.isTrue(await marketplace.isPaymentToken(usdtToken.address));
            assert.isTrue(await marketplace.isPaymentToken(fcqToken.address));
        });
    });

    describe("Marketplace orders:", function() {
        it("should add token buy order", async () => {
           expiryTime = await helpers.latestTime() + helpers.duration.weeks(1);
           // buyer approves marketplace to spend its USDT tokens (100 + 1% fee)
           await usdtToken.approve(marketplace.address, 101e6, { from: buyer });
           // add new order to buy 1 equity token for 100 USDT
           await marketplace.addOrder(expiryTime, usdtToken.address, 100e6, token.address, 1, {from: buyer});
           // check order
           order = await marketplace.order(1);
           assert.equal(order[0], expiryTime);
           assert.equal(order[1], usdtToken.address);
           assert.equal(order[2], 100e6);
           assert.equal(order[3], token.address);
           assert.equal(order[4], 1);
           assert.equal(order[5], buyer);
           assert.equal(order[6], 1e6);
        });

        it("should add token sell order", async () => {
            expiryTime = await helpers.latestTime() + helpers.duration.weeks(1);
            // seller approves marketplace to spend its Equity tokens
            await token.approve(marketplace.address, 1, { from: seller });
            // add new order to sell 1 equity token for 100 USDT
            await marketplace.addOrder(expiryTime, token.address, 1, usdtToken.address, 100e6, {from: seller});
            // check order
            order = await marketplace.order(1);
            assert.equal(order[0], expiryTime);
            assert.equal(order[1], token.address);
            assert.equal(order[2], 1);
            assert.equal(order[3], usdtToken.address);
            assert.equal(order[4], 100e6);
            assert.equal(order[5], seller);
            assert.equal(order[6], 1e6);
        });

        it("should revert add order", async () => {
            expiryTime = await helpers.latestTime() + helpers.duration.weeks(1);
            // reverts when buyer didn't approve marketplace to spend its tokens
            await truffleAssert.reverts(
                marketplace.addOrder(expiryTime, usdtToken.address, 100e6, token.address, 1, {from: buyer})
            );
            // buyer approves marketplace to spend its USDT tokens (100 + 1% fee)
            await usdtToken.approve(marketplace.address, 101e6, { from: buyer });
            // reverts when offer is to buy for 0 USDT
            await truffleAssert.reverts(
                marketplace.addOrder(expiryTime, usdtToken.address, 0, token.address, 1, {from: buyer})
            );
            // reverts when offer is to buy 0 tokens
            await truffleAssert.reverts(
                marketplace.addOrder(expiryTime, usdtToken.address, 100e6, token.address, 0, {from: buyer})
            );
            // reverts when token addresses are wrong (one has to be allowed payment and second allowed equity token)
            await truffleAssert.reverts(
                marketplace.addOrder(expiryTime, usdtToken.address, 100e6, usdtToken.address, 1, {from: buyer})
            );
        });

        it("should remove order", async () => {
            expiryTime = await helpers.latestTime() + helpers.duration.weeks(1);
            balanceBefore = await usdtToken.balanceOf(buyer);
            await usdtToken.approve(marketplace.address, 101e6, { from: buyer });
            // add new order
            await marketplace.addOrder(expiryTime, usdtToken.address, 100e6, token.address, 1, {from: buyer});
            assert.equal(await usdtToken.balanceOf(buyer), balanceBefore-101e6)
            // remove order
            await marketplace.removeOrder(1, {from: buyer});
            // check if order returned locked funds
            assert.equal(await usdtToken.balanceOf(buyer), balanceBefore.toNumber());
        });

        it("should process the buy order", async () => {
            expiryTime = await helpers.latestTime() + helpers.duration.weeks(1);
            buyerUSDTBalanceBefore = await usdtToken.balanceOf(buyer);
            sellerUSDTBalanceBefore = await usdtToken.balanceOf(seller);
            buyerTokenBalanceBefore = await token.balanceOf(buyer);
            sellerTokenBalanceBefore = await token.balanceOf(seller);
            walletBalanceBefore = await usdtToken.balanceOf(wallet);
            // buyer approves marketplace to spend its USDT tokens (100 + 1% fee
            await usdtToken.approve(marketplace.address, 101e6, { from: buyer });
            // add new order
            await marketplace.addOrder(expiryTime, usdtToken.address, 100e6, token.address, 1, {from: buyer});
            // seller approves marketplace to spend its equity tokens
            await token.approve(marketplace.address, 1, { from: seller });
            // process order
            await marketplace.processOrder(1, seller, { from: platform });
            // check balances
            assert.equal(await usdtToken.balanceOf(buyer), buyerUSDTBalanceBefore-101e6);
            assert.equal(await usdtToken.balanceOf(seller), sellerUSDTBalanceBefore.toNumber()+99e6);
            assert.equal(await token.balanceOf(buyer), buyerTokenBalanceBefore.toNumber()+1);
            assert.equal(await token.balanceOf(seller), sellerTokenBalanceBefore.toNumber()-1);
            assert.equal(await usdtToken.balanceOf(wallet), walletBalanceBefore.toNumber()+2e6);
        });
        
        it("should NOT process order after expiry time", async () => {
            expiryTime = await helpers.latestTime() + helpers.duration.weeks(1);
            await usdtToken.approve(marketplace.address, 101e6, { from: buyer });
            await marketplace.addOrder(expiryTime, usdtToken.address, 100e6, token.address, 1, {from: buyer});
            await token.approve(marketplace.address, 1, { from: seller });
            // increase time in order to expire the order
            await helpers.increaseTimeTo(expiryTime + helpers.duration.days(1));
            // expired order cannot be processed
            await truffleAssert.reverts(
                marketplace.processOrder(1, seller, { from: platform })
            );
        });
    });
})