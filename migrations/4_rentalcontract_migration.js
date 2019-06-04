var RentalContract = artifacts.require("RentalContract");
var LinkToken = artifacts.require("LinkToken");
var Oracle = artifacts.require("Oracle");

module.exports = (deployer, network, accounts) => {
  deployer.deploy(RentalContract, LinkToken.address, Oracle.address, {from: accounts[0]});
};