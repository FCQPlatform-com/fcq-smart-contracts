const truffleAssert = require('truffle-assertions');
const helpers = require('truffle-test-helpers');
const USDTToken = artifacts.require("MockUSDTToken");
const FCQToken = artifacts.require("FCQToken");
const DAIToken = artifacts.require("MockDAIToken");
const EquityToken = artifacts.require("EquityToken");
const InvestmentFactory = artifacts.require("InvestmentFactory");
const InvestmentFundraise = artifacts.require("InvestmentFundraise");

contract("InvestmentFundraise", async accounts => {
    let owner = accounts[0];
    let platform = accounts[1];
    let operator = accounts[2];
    let investor = accounts[3];
    let endTime;
    let investmentFundraise;

    before(async function() {
        // Advance to the next block to correctly read time in the solidity "timestamp" function interpreted by ganache
        await helpers.advanceBlock();
    });

    beforeEach(async function () {
        // deploy new investment fundraise before every test
        investmentFactory = await InvestmentFactory.deployed();
        token = await EquityToken.deployed();
        usdtToken = await USDTToken.new();
        usdcToken = await USDTToken.new();
        fcqToken = await FCQToken.new();
        daiToken = await DAIToken.new();
        endTime = await helpers.latestTime() + helpers.duration.weeks(1);
        res = await investmentFactory.create(
            web3.utils.fromAscii("Office"), // investment name
            100000e6, // goal amount to collect in USD
            endTime, // end time
            owner, // investment wallet 
            token.address, // equity token address
            [fcqToken.address, usdtToken.address, usdcToken.address, daiToken.address], // payment token addresses
            [2e6, 1, 1, -1e12],
            {from: platform} // caller is platform
        );
        investmentFundraise = await InvestmentFundraise.at(res.logs[0].args[1]);
        // set fundraise as issuer
        token.setIssuer(investmentFundraise.address);
        // fill inwestor wallet with USDT
        await usdtToken.transfer(investor, 1000000e6, { from: owner });
        // fill inwestor wallet with USDC
        await usdcToken.transfer(investor, 1000000e6, { from: owner });
        // fill inwestor wallet with FCQ
        await fcqToken.transfer(investor, 1000000, { from: owner });
        // fill inwestor wallet with DAI (1000e18)
        await daiToken.transfer(investor, "1000000000000000000000", {from: owner});
    });

    describe("investment creation:", function() {
        it("should create investment", async () => {
            let tokens = await investmentFundraise.paymentTokens();
            assert.equal(tokens[0], fcqToken.address);
            assert.equal(tokens[1], usdtToken.address);
            assert.equal(tokens[2], usdcToken.address);
            assert.equal(await investmentFundraise.fcqToken(), fcqToken.address);
            assert.equal(await investmentFundraise.tokenRate(fcqToken.address), 2e6);
            assert.equal(await investmentFundraise.wallet(), owner);
            assert.equal(await investmentFundraise.token(), token.address);
            assert.equal(await investmentFundraise.name(), web3.utils.padRight(web3.utils.fromAscii("Office"), 64));
            assert.equal(await investmentFundraise.endTime(), endTime);
            assert.equal(await investmentFundraise.cap(), 100000e6);
        });
    });

    describe("investment fundraise payment:", function() {
        it("should accept payment in USDT", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 100e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 100e6, { from: investor });
            // check if USDT tokens were transfered
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 100e6);
            // check if fundraise noted the payment
            assert.equal(await investmentFundraise.paidForAccount(usdtToken.address, accountId), 100e6);
            assert.equal(await investmentFundraise.paid(usdtToken.address, investor), 100e6);
            assert.equal(await investmentFundraise.getAmountPaidInUSD(accountId), 100e6);
        });

        it("should accept payment in USDC and USDT", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT and USDC tokens
            await usdcToken.approve(investmentFundraise.address, 100e6, { from: investor });
            await usdtToken.approve(investmentFundraise.address, 100e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdcToken.address, accountId, 100e6, { from: investor });
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 100e6, { from: investor });
            // check if USDC tokens were transfered
            assert.equal(await usdcToken.balanceOf(investmentFundraise.address), 100e6);
            // check if fundraise noted the payment
            assert.equal(await investmentFundraise.paidForAccount(usdcToken.address, accountId), 100e6);
            assert.equal(await investmentFundraise.paid(usdcToken.address, investor), 100e6);
            assert.equal(await investmentFundraise.getAmountPaidInUSD(accountId), 200e6);
        });

        it("should accept payment in DAI", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its DAI tokens
            await daiToken.approve(investmentFundraise.address, "100000000000000000000" /*100e18*/, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(daiToken.address, accountId, "100000000000000000000" /*100e18*/, { from: investor });
            // check if DAI tokens were transfered
            assert.equal(await daiToken.balanceOf(investmentFundraise.address), "100000000000000000000" /*100e18*/);
            // check if fundraise noted the payment
            assert.equal(await investmentFundraise.paidForAccount(daiToken.address, accountId), "100000000000000000000" /*100e18*/);
            assert.equal(await investmentFundraise.paid(daiToken.address, investor), "100000000000000000000" /*100e18*/);
            assert.equal(await investmentFundraise.getAmountPaidInUSD(accountId), 100e6);
        });

        it("should accept payment in FCQ", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 100, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its FCQ tokens
            await fcqToken.approve(investmentFundraise.address, 100, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(fcqToken.address, accountId, 100, { from: investor });
            // check if FCQ tokens were transfered
            assert.equal(await fcqToken.balanceOf(investmentFundraise.address), 100);
            // check if fundraise noted the payment
            assert.equal(await investmentFundraise.paidForAccount(fcqToken.address, accountId), 100);
            assert.equal(await investmentFundraise.paid(fcqToken.address, investor), 100);
            assert.equal(await investmentFundraise.getAmountPaidInUSD(accountId), 200e6);
        });

        it("should accept payment in FCQ with approveAndCall", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 100, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its FCQ tokens and triggers payment
            await fcqToken.approveAndCall(investmentFundraise.address, 100, web3.utils.padLeft(web3.utils.toHex(accountId), 64), { from: investor });
            // check if FCQ tokens were transfered
            assert.equal(await fcqToken.balanceOf(investmentFundraise.address), 100);
            // check if fundraise noted the payment
            assert.equal(await investmentFundraise.paidForAccount(fcqToken.address, accountId), 100);
            assert.equal(await investmentFundraise.paid(fcqToken.address, investor), 100);
            assert.equal(await investmentFundraise.getAmountPaidInUSD(accountId), 200e6);
        });

        it("should not accept payment in FCQ over the limit", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 100, 100, { from: platform });
            accountId = res.logs[0].args[0];
            await fcqToken.transfer(investor, 200, { from: owner });
            await truffleAssert.reverts(
                // fcq payment is reverted due to 100 limit
                fcqToken.approveAndCall(investmentFundraise.address, 101, web3.utils.padLeft(web3.utils.toHex(accountId), 64), { from: investor })
            );
        });
    });

    describe("investment time limit:", function() {
        it("should not accept payment after end time", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 100e6, { from: investor });
            // increase time to 1 day after end time
            await helpers.increaseTimeTo(endTime + helpers.duration.days(1));
            // payments reverts after end time
            await truffleAssert.reverts(
                // platform triggers payment with investor data
                investmentFundraise.payWithToken(usdtToken.address, accountId, 100e6, { from: investor })
            );
        });
    });

    describe("investment cap limit:", function() {
        it("should not accept payment after cap", async () => {
            // cap is 200000e6 and created accaunt payment exceeds cap
            res = await investmentFundraise.createFundraiseAccount(investor, 150000e6, 0, 200, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 150000e6, { from: investor });
            // payment reverts when cap exceeded
            await truffleAssert.reverts(
                // platform triggers payment with investor data
                investmentFundraise.payWithToken(usdtToken.address, accountId, 150000e6, { from: investor })
            );
        })
    })

    describe("investment refund:", function() {
        it("should refund when member didn't pay full amount and fundraise was finalized", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            beforeBalance = await usdtToken.balanceOf(investor);
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 100e6, { from: investor });
            // platform triggers payment with investor data
            investmentFundraise.payWithToken(usdtToken.address, accountId, 100e6, { from: investor })
            // finalize fundraise
            investmentFundraise.finalize(true, { from: operator });
            // check if fundraise noted the payment
            assert.equal(await investmentFundraise.paidForAccount(usdtToken.address, accountId), 100e6);
            assert.equal(await investmentFundraise.paid(usdtToken.address, investor), 100e6);
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 100e6);
            assert.equal(await usdtToken.balanceOf(investor), beforeBalance-100e6);
            // refund
            investmentFundraise.claimRefundForAccount(accountId);
            // check if fundraise noted the refund
            assert.equal(await investmentFundraise.paidForAccount(usdtToken.address, accountId), 0);
            assert.equal(await investmentFundraise.paid(usdtToken.address, investor), 0);
            // check balances
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 0);
            assert.equal(await usdtToken.balanceOf(investor), beforeBalance.toNumber());
        })

        it("should refund when an account was blocklisted", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            beforeBalance = await usdtToken.balanceOf(investor);
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 1000e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 1000e6, { from: investor });
            // check if fundraise noted the payment
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 1000e6);
            // blocklist account
            await investmentFundraise.blocklistAccount(accountId, { from: platform });
            assert.isTrue(await investmentFundraise.isBlocklistedAccount(accountId));
            // refund
            await investmentFundraise.claimRefundForAccount(accountId);
            // check balances
            assert.equal(await investmentFundraise.paidForAccount(usdtToken.address, accountId), 0);
            assert.equal(await investmentFundraise.paid(usdtToken.address, investor), 0);
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 0);
            assert.equal(await usdtToken.balanceOf(investor), beforeBalance.toNumber());
        })

        it("should refund when a member was blocklisted", async () => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            beforeBalance = await usdtToken.balanceOf(investor);
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 1000e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 1000e6, { from: investor });
            // check if fundraise noted the payment
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 1000e6);
            // blocklist account
            await investmentFundraise.blocklistWallet(investor, { from: platform });
            assert.isTrue(await investmentFundraise.isBlocklistedWallet(investor));
            // refund
            await investmentFundraise.claimRefund(investor);
            // check balances
            assert.equal(await investmentFundraise.paid(usdtToken.address, investor), 0);
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 0);
            assert.equal(await usdtToken.balanceOf(investor), beforeBalance.toNumber());
        })

        it("should refund when fundrise was not succesfull", async() => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            beforeBalance = await usdtToken.balanceOf(investor);
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 1000e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 1000e6, { from: investor });
            // check if fundraise noted the payment
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 1000e6);
            // finalize fundraise with failure
            await investmentFundraise.finalize(false, { from: operator });
            assert.isFalse(await investmentFundraise.wasSuccessfullyFinalized());
            // refund
            await investmentFundraise.claimRefundForAccount(accountId);
            await investmentFundraise.claimRefund(investor);
            // check balances
            assert.equal(await investmentFundraise.paid(usdtToken.address, investor), 0);
            assert.equal(await usdtToken.balanceOf(investmentFundraise.address), 0);
            assert.equal(await usdtToken.balanceOf(investor), beforeBalance.toNumber());
        })
    })

    describe("token delivery:", function() {
        it("should withdraw tokens when fundrise was succesfull", async() => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 1000e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 1000e6, { from: investor });
            // finalize fundraise with success
            await investmentFundraise.finalize(true, { from: operator });
            // withdraw tokens
            await investmentFundraise.withdrawTokens(accountId);
            // check tokens delivery
            assert.equal(await token.balanceOf(investor), 100);
        })

        it("should withdraw tokens for all accounts when fundrise was succesfull", async() => {
            beforeBalance = await token.balanceOf(investor);
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            firstAccountId = res.logs[0].args[0];
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            secondAccountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 2000e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, firstAccountId, 1000e6, { from: investor });
            await investmentFundraise.payWithToken(usdtToken.address, secondAccountId, 1000e6, { from: investor });
            // finalize fundraise with success
            await investmentFundraise.finalize(true, { from: operator });
            // withdraw tokens
            await investmentFundraise.withdrawAccountsTokens([firstAccountId, secondAccountId]);
            // check tokens delivery
            assert.equal(await token.balanceOf(investor), beforeBalance.toNumber()+200);
        })

        it("should NOT withdraw tokens when fundrise was succesfull and account was blocklisted", async() => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 1000e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 1000e6, { from: investor });
            // finalize fundraise with success
            await investmentFundraise.finalize(true, { from: operator });
            // blocklist account
            await investmentFundraise.blocklistAccount(accountId, { from: platform });
            // check if withdraw tokens is reverted
            await truffleAssert.reverts(
                investmentFundraise.withdrawTokens(accountId)
            );
        })

        it("should NOT withdraw tokens when fundrise was succesfull and member was blocklisted", async() => {
            res = await investmentFundraise.createFundraiseAccount(investor, 1000e6, 0, 100, { from: platform });
            accountId = res.logs[0].args[0];
            // investor approves fundraise to spend its USDT tokens
            await usdtToken.approve(investmentFundraise.address, 1000e6, { from: investor });
            // platform triggers payment with investor data
            await investmentFundraise.payWithToken(usdtToken.address, accountId, 1000e6, { from: investor });
            // finalize fundraise with success
            await investmentFundraise.finalize(true, { from: operator });
            // blocklist investor
            await investmentFundraise.blocklistWallet(investor, { from: platform });
            // check if withdraw tokens is reverted
            await truffleAssert.reverts(
                investmentFundraise.withdrawTokens(accountId)
            );
        })
    })
});
