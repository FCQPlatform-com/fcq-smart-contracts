const truffleAssert = require('truffle-assertions');
const EquityToken = artifacts.require("EquityToken");
const MockUSDTToken = artifacts.require("MockUSDTToken");
const MockTransferValidator = artifacts.require("./MockTransferValidator.sol");
const TransferValidator = artifacts.require("./TransferValidator.sol");

contract("EquityToken", async accounts => {
    let token;
    let usdtToken;
    let owner = accounts[0];
    let issuer = accounts[1];

    beforeEach(async function () {
        // deploy new token before every test
        transferValidator = await MockTransferValidator.new();
        usdtToken = await MockUSDTToken.deployed();
        token = await EquityToken.new("EquityToken", "ET", transferValidator.address, usdtToken.address);
        // set token issuer 
        await token.setIssuer(issuer, { from: owner });
    });

    describe("token issuance:", function() {
        it("should issue tokens by the issuer", async () => {
            // issue 10 tokens to accounts[2] by issuer
            let isIssuer = await token.isIssuer(issuer);
            assert.isTrue(isIssuer);
            await token.issue(accounts[2], 10, '0x', { from: issuer });
            // check balance for accounts[2]
            assert.equal(await token.balanceOf(accounts[2]), 10);
            assert.equal(await token.totalSupply(), 10);
        });

        it("should stop issuance", async () => {
            // issue 10 tokens to accounts[2] by issuer
            await token.issue(accounts[2], 10, '0x', { from: issuer });
            // renounce issuance by issuer  
            await token.renounceIssuance({ from: issuer });
            assert.isFalse(await token.isIssuable());
            // after renounceIssuance is not possible to issue more tokens
            await truffleAssert.reverts(
                token.issue(accounts[2], 10, '0x', { from: issuer })
            );
        })
    });

    describe("token transfers:", function() {
        it("should transfer tokens", async () => {
            // issue 10 tokens to accounts[2] by issuer
            await token.issue(accounts[2], 10, '0x', { from: issuer });
            // transfer 5 tokens from account[2] to account[3]
            await token.transfer(accounts[3], 5, { from: accounts[2] });
            // check balance for token sender and receiver
            assert.equal(await token.balanceOf(accounts[2]), 5);
            assert.equal(await token.balanceOf(accounts[3]), 5);
        });
    });

    describe("token dividends:", function() {
        it("should distribute dividends", async () => {
            // issue 10 tokens to accounts[2], 20 tokens to accounts[3], 30 tokens to accounts[4] 
            await token.issue(accounts[2], 10, '0x', { from: issuer });
            await token.issue(accounts[3], 20, '0x', { from: issuer });
            await token.issue(accounts[4], 30, '0x', { from: issuer });
            // distribute 60 USDT tokens of dividend
            await usdtToken.transfer(token.address, 60e6);
            await token.distributeDividends(60e6);
            // check dividends for accounts
            assert.equal(await token.dividendOf(accounts[2]), 10e6);
            assert.equal(await token.dividendOf(accounts[3]), 20e6);
            assert.equal(await token.dividendOf(accounts[4]), 30e6);
        });

        it("should distribute correct dividends after transfers", async () => {
            // issue 10 tokens to accounts[2], 20 tokens to accounts[3]
            await token.issue(accounts[2], 10, '0x', { from: issuer });
            await token.issue(accounts[3], 20, '0x', { from: issuer });
            // distribute 30 USDT tokens of dividend
            await token.distributeDividends(30e6);
            // transfer 5 tokens from account[2] to account[3]
            await token.transfer(accounts[3], 5, { from: accounts[2] });
            // check dividends for accounts after transfers - it shouldn't change
            assert.equal(await token.dividendOf(accounts[2]), 10e6);
            assert.equal(await token.dividendOf(accounts[3]), 20e6);
            // distribute another dividend - 30 USDT tokens
            await token.distributeDividends(30e6);
            assert.equal(await token.dividendOf(accounts[2]), 15e6);
            assert.equal(await token.dividendOf(accounts[3]), 45e6);
        });

        it("should withdraw dividend", async () => {
            // issue 10 tokens to accounts[2], 20 tokens to accounts[3]
            await token.issue(accounts[2], 10, '0x', { from: issuer });
            await token.issue(accounts[3], 20, '0x', { from: issuer });
            // distribute 30 USDT tokens of dividend
            await usdtToken.transfer(token.address, 30e6);
            await token.distributeDividends(30e6);
            // withdraw dividend by account[2]
            await token.withdrawDividend(accounts[2]);
            // check if the withdrawn dividend was successful and balances were updated properly
            assert.equal(await token.withdrawnDividendOf(accounts[2]), 10e6);
            assert.equal(await token.dividendOf(accounts[2]), 0);
            assert.equal(await usdtToken.balanceOf(accounts[2]), 10e6);
        });

        it("should withdraw dividends for investors", async () => {
            beforeBalanceAccount2 = await usdtToken.balanceOf(accounts[2]);
            beforeBalanceAccount3 = await usdtToken.balanceOf(accounts[3]);
            // issue 10 tokens to accounts[2], 20 tokens to accounts[3]
            await token.issue(accounts[2], 10, '0x', { from: issuer });
            await token.issue(accounts[3], 20, '0x', { from: issuer });
            // distribute 30 USDT tokens of dividend
            await usdtToken.transfer(token.address, 30e6);
            await token.distributeDividends(30e6);
            // withdraw dividends for account[2] and account[3]
            await token.withdrawDividends([accounts[2], accounts[3]]);
            // check if the withdrawn dividend was successful and balances were updated properly
            assert.equal(await token.withdrawnDividendOf(accounts[2]), 10e6);
            assert.equal(await token.dividendOf(accounts[2]), 0);
            assert.equal(await usdtToken.balanceOf(accounts[2]), beforeBalanceAccount2.toNumber() + 10e6);
            assert.equal(await token.withdrawnDividendOf(accounts[3]), 20e6);
            assert.equal(await token.dividendOf(accounts[3]), 0);
            assert.equal(await usdtToken.balanceOf(accounts[3]), beforeBalanceAccount3.toNumber() + 20e6);
        });
    });
    
    describe("token transfers validity:", function() {
        beforeEach(async function () {
            // set proper transfer validator
            transferValidator = await TransferValidator.deployed();
            await token.setTransferValidator(transferValidator.address);
            // issue 10 tokens to accounts[2] by issuer
            await token.issue(accounts[2], 10, '0x', { from: issuer });
        });

        it("should be able to transfer tokens as an authority", async () => {
            // make accounts[2] authority to be able to process token transfers
            await transferValidator.registerTokenAuthorities(token.address, [accounts[2]]);
            assert.isTrue(await transferValidator.isTokenAuthority(token.address, accounts[2]));
            // check if accounts[2] can transfer 5 tokens to account[3]
            canTransfer = await token.canTransfer(accounts[3], 5, '0x', { from: accounts[2]});
            assert.isTrue(canTransfer[0]);
            // transfer 5 tokens to account[3]
            await token.transfer(accounts[3], 5, { from: accounts[2] });
            // check balance for token sender and receiver
            assert.equal(await token.balanceOf(accounts[2]), 5);
            assert.equal(await token.balanceOf(accounts[3]), 5);
        });

        it("should be able to transfer from through authority", async () => {
            // accounts[2] approves authority to transfer 5 tokens
            await token.approve(owner, 5, { from: accounts[2] });
            // check if authority can transfer 5 tokens from account[2] to account[3]
            canTransferFrom = await token.canTransferFrom(accounts[2], accounts[3], 5, '0x', { from: owner});
            assert.isTrue(canTransferFrom[0]);
            // transfer 5 tokens to account[3] as an authority
            await token.transferFrom(accounts[2], accounts[3], 5, { from: owner});
            // check balance for token sender and receiver
            assert.equal(await token.balanceOf(accounts[2]), 5);
            assert.equal(await token.balanceOf(accounts[3]), 5);
        });

        it("should be able to transfer using authorized certificate", async () => {
            // get nonce for token and sender address
            const nonce = await transferValidator.usedCertificateNonce(token.address, accounts[2]);
            // create certificate and sign it
            const expireTime = web3.utils.padLeft(web3.utils.toHex(16725225600), 64);
            const value = web3.utils.padLeft(web3.utils.toHex(5), 64);
            const nonceHex = web3.utils.padLeft(web3.utils.toHex(nonce.toNumber()), 64);
            const hash = web3.utils.sha3(accounts[2] + token.address.substring(2) + accounts[2].substring(2) + accounts[3].substring(2) + 
                value.substring(2) + expireTime.substring(2) + nonceHex.substring(2), {encoding:"hex"});
            const signature = await web3.eth.sign(hash, owner);
            const certificate = expireTime + signature.substring(2);
            // check if accounts[2] can transfer 5 tokens to account[3] using certificate
            canTransfer = await token.canTransfer(accounts[3], 5, certificate, { from: accounts[2]});
            assert.isTrue(canTransfer[0]);
            //  transfer 5 tokens to account[3] using certificate
            await token.transferWithData(accounts[3], 5, certificate, { from: accounts[2] });
            // check balance for token sender and receiver
            assert.equal(await token.balanceOf(accounts[2]), 5);
            assert.equal(await token.balanceOf(accounts[3]), 5);
        });
    });
});
