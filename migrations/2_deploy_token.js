const { MichelsonMap } = require("@taquito/taquito");
const { alice, bob } = require("../scripts/sandbox/accounts");

const FA12token = artifacts.require("FA12token");

const initialStorage = {
  totalSupply: 350,
  ledger: MichelsonMap.fromLiteral({
    [alice.pkh]: { balance: 200, allowances: new MichelsonMap() },
    [bob.pkh]: { balance: 150, allowances: new MichelsonMap() }
  })
};

module.exports = async (deployer, _network) => {
  deployer.deploy(FA12token, initialStorage);
};
