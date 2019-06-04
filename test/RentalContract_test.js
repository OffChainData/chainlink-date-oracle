"use strict";

const h = require("chainlink-test-helpers");
const truffleAssert = require('truffle-assertions');


contract("RentalContract", (accounts) => {
    const LinkToken = artifacts.require("LinkToken.sol");
    const Oracle = artifacts.require("Oracle.sol");
    const RentalContract = artifacts.require("RentalContract.sol");
    const defaultAccount = accounts[0];
    const oracleNode = accounts[1];
    const stranger = accounts[2];
    const consumer = accounts[3];
    const jobId = web3.utils.toHex("4c7b7ffb66b344fbaa64995af81e355a");
    const region = "AU-QLD";
    let link, oc, cc;

    beforeEach(async () => {
        link = await LinkToken.new();
        oc = await Oracle.new(link.address, {from: defaultAccount});
        cc = await RentalContract.new(link.address, oc.address, {from: consumer});
        await oc.setFulfillmentPermission(oracleNode, true, {from: defaultAccount});
        //fund the consumer contract with 1 eth
        await cc.send(web3.utils.toWei("1", "ether"), {from: defaultAccount});
    });
  
    describe("Create a request", () => {
        context("Without LINK", () => {
            it("reverts", async () => {
                await h.assertActionThrows(async () => {
                await cc.checkDate(jobId, web3.utils.fromAscii('2019-01-02'), 
                        web3.utils.fromAscii(region), 
                        {from: consumer});
                });
            });
        });

        context("With LINK", () => {
            let request;
        
            beforeEach(async () => {
                await link.transfer(cc.address, web3.utils.toWei("1", "ether"));
            });

            it("triggers a log event in the Oracle contract", async () => {
                const tx = await cc.checkDate(jobId, web3.utils.fromAscii('2019-01-02'), 
                                    web3.utils.fromAscii(region), 
                                    {from: consumer});
                request = h.decodeRunRequest(tx.receipt.rawLogs[3]);
                assert.equal(oc.address, tx.receipt.rawLogs[3].address);
                assert.equal(request.topic, web3.utils.keccak256("OracleRequest(bytes32,address,bytes32,uint256,address,bytes4,uint256,uint256,bytes)"));
                
            });
        });
    });


    describe("Fulfill a request", () => {
       context("With LINK", () => {
            let request;
        
            beforeEach(async () => {
                await link.transfer(cc.address, web3.utils.toWei("1", "ether"));
            });

            it("Business days of month is set", async () => {
                const expected = "1";
                const response = web3.utils.fromAscii(expected);     
                
                const tx = await cc.checkDate(jobId, '2019-01-02', 
                                    region, 
                                    {from: consumer});
                request = h.decodeRunRequest(tx.receipt.rawLogs[3]);
                await h.fulfillOracleRequest(oc, request, response, {from: oracleNode});
                
                //Date was requested and should be fulfilled
                let wd = await cc.businessDayOfMonth.call(web3.utils.toHex('2019-01-02'));
                assert.equal(expected, web3.utils.toUtf8(wd));

                //Date was not requested
                wd = await cc.businessDayOfMonth.call(web3.utils.toHex('2019-01-01'));
                assert.equal("", web3.utils.toUtf8(wd));
            });

            it("Payment should not be made", async () => {
                const date = web3.utils.fromAscii('2019-01-03');
                const response = web3.utils.fromAscii("2");     
                const tx = await cc.checkDate(jobId, web3.utils.fromAscii(date), 
                                    web3.utils.fromAscii(region), 
                                    {from: consumer});
                request = h.decodeRunRequest(tx.receipt.rawLogs[3]);
                await h.fulfillOracleRequest(oc, request, response, {from: oracleNode});
                
                //2nd working day of month is not a payment day
                const pd = await cc.paidDates.call(web3.utils.toHex(date));
                assert.equal(false, pd);
                const balance = await web3.eth.getBalance(cc.address)
                assert.equal(1, web3.utils.fromWei(balance, 'ether'));
            });

            it("Payment should be made", async () => {
                const date = '2019-01-02';
                const response = web3.utils.fromAscii("1");     
                const tx = await cc.checkDate(jobId, date, 
                                    region, 
                                    {from: consumer});
                request = h.decodeRunRequest(tx.receipt.rawLogs[3]);
                await h.fulfillOracleRequest(oc, request, response, {from: oracleNode});
                
                //1st working day of month is a payment day
                const pd = await cc.paidDates.call(web3.utils.fromAscii(date));
                assert.equal(true, pd);

                const currentRent = await cc.getRentalAmount();
                const balance = await web3.eth.getBalance(cc.address)
                assert.equal((web3.utils.toWei("1", "ether") - currentRent), balance);

            });
        });
    });

    describe("Set control variables", () => {
        beforeEach(async () => {
            await link.transfer(cc.address, web3.utils.toWei("1", "ether"));
        });

        context("When called by the owner", () => {
            
            it("Sets the monthly rental amount", async () => {
                const currentRent = await cc.getRentalAmount();
                assert.equal('0.01', web3.utils.fromWei(currentRent, 'ether'));
                
                await cc.setRentalAmount(2000000, {from: consumer});
                
                const newRent = await cc.getRentalAmount();
                assert.equal(2000000, newRent);
            });

            it("Region must not be empty", async () => {
                const currentDate = await cc.currentDate.call();
                assert.equal(0, web3.utils.toUtf8(currentDate));
                
                await truffleAssert.reverts(
                    cc.checkDate(jobId, '2019-01-02', 
                                        '', 
                                        {from: consumer}), "Region must be set."
                    );
            });
        })
    });
});