const FA12token = artifacts.require("FA12token");
const { Tezos } = require("@taquito/taquito");
const { InMemorySigner } = require("@taquito/signer");
const truffleConfig = require("../truffle-config");
const { alice, bob } = require("../scripts/sandbox/accounts");

const signerFactory = async pk => {
  await Tezos.setProvider({ signer: new InMemorySigner(pk) });
  return Tezos;
};

contract("FA1.2 Token", () => {
  let storage, contractInstance;

  before(async () => {
    Tezos.setProvider({
      rpc: `${truffleConfig.networks.development.host}:${truffleConfig.networks.development.port}`
    });
    await signerFactory(alice.sk);
    const instance = await FA12token.deployed();
    /**
     * Display the current contract address for debugging purposes
     */
    console.log("Contract deployed at:", instance.address);

    contractInstance = await Tezos.wallet.at(instance.address);

    storage = await contractInstance.storage();
  });

  // checks total supply
  it("should have a total supply set to 0", async () => {
    assert.equal(storage.totalSupply, 350);
  });

  // checks Alice's and Bob's balances
  it("Alice should have 200 tokens, Bob 150", async () => {
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const bobAccount = await storage.ledger.get(bob.pkh);

    assert.equal(aliceAccount.balance, 200);
    assert.equal(bobAccount.balance, 150);
  });

  // Alice approves 100 tokens to be transferred by Bob
  it("should change Bob's allowance for Alice's tokens to 100", async () => {
    const allowance = 100;
    let bobAllowance = 0;
    try {
      // sends approval transaction
      const op = await contractInstance.methods
        .approve(bob.pkh, allowance)
        .send();
      await op.confirmation();
      // updates storage
      storage = await contractInstance.storage();
      // fetches new allowance from Alice's account
      const aliceAccount = await storage.ledger.get(alice.pkh);
      bobAllowance = await aliceAccount.allowances.get(bob.pkh);
    } catch (err) {
      console.log(err);
    }

    assert.equal(bobAllowance, allowance);
  });

  // should prevent Alice to send tokens to herself
  it("should prevent Alice to send tokens to herself", async () => {
    let error = undefined;

    try {
      const op = await contractInstance.methods
        .transfer(alice.pkh, alice.pkh, 100)
        .send();
      await op.confirmation();
    } catch (err) {
      error = err;
    }

    assert.equal(error.message, "InvalidSelfToSelfTransfer");
  });

  // should send 10 tokens from Alice to Bob
  it("should transfer 10 tokens from Alice to Bob", async () => {
    const tokens = 10;
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const bobAccount = await storage.ledger.get(bob.pkh);
    let bobNewAccount, aliceNewAccount;

    try {
      // sends transfer
      const op = await contractInstance.methods
        .transfer(alice.pkh, bob.pkh, tokens)
        .send();
      await op.confirmation();
      // updates storage
      storage = await contractInstance.storage();
      // checks Bob's new balance
      bobNewAccount = await storage.ledger.get(bob.pkh);
      // checks Alice's new balance
      aliceNewAccount = await storage.ledger.get(alice.pkh);
      //console.log(bobNewAccount, aliceNewAccount);
    } catch (err) {
      console.log(err);
    }

    assert.equal(
      bobNewAccount.balance.toNumber(),
      bobAccount.balance.toNumber() + 10
    );
    assert.equal(
      aliceNewAccount.balance.toNumber(),
      aliceAccount.balance.toNumber() - 10
    );
  });

  // should prevent Bob to exceed his allowance or Alice's balance
  it("should prevent Bob to exceed his allowance", async () => {
    let error;

    await signerFactory(bob.sk);

    try {
      const op = await contractInstance.methods
        .transfer(alice.pkh, bob.pkh, 300)
        .send();
      await op.confirmation();
    } catch (err) {
      error = err.message;
    }

    assert.equal(error, "NotEnoughBalance");

    try {
      const op = await contractInstance.methods
        .transfer(alice.pkh, bob.pkh, 150)
        .send();
      await op.confirmation();
    } catch (err) {
      error = err.message;
    }

    assert.equal(error, "NotEnoughAllowance");
  });

  // should let Bob spend half of his allowance
  it("should let Bob spend half of his allowance", async () => {
    const aliceAccount = await storage.ledger.get(alice.pkh);
    const bobAllowance = await aliceAccount.allowances.get(bob.pkh);
    let bobNewAllowance, aliceNewAccount;

    try {
      const op = await contractInstance.methods
        .transfer(alice.pkh, bob.pkh, bobAllowance.toNumber() / 2)
        .send();
      await op.confirmation();
      // fetches updated account
      aliceNewAccount = await storage.ledger.get(alice.pkh);
      bobNewAllowance = await aliceNewAccount.allowances.get(bob.pkh);
    } catch (err) {
      console.log(err);
    }

    assert.equal(bobNewAllowance, bobAllowance.toNumber() / 2);
    assert.equal(
      aliceNewAccount.balance.toNumber(),
      aliceAccount.balance.toNumber() - bobAllowance.toNumber() / 2
    );
  });
});
