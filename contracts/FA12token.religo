// Implimentation of the FA1.2 specification in ReasonLIGO 
// Based on PascaLigo implementation from https://ide-staging.ligolang.org/p/xHuzW6APAZK8K7UDRffUXg

// Define types 
type trusted = address
type amt = nat

type account = {
  balance    : amt,
  allowances : map (trusted, amt)
}

// contract storage 
type storage = {
  totalSupply : amt,
  ledger      : big_map (address, account)
}

// define return for readability 
type return = (list (operation), storage);

// Inputs 
type transferParams = michelson_pair(address, "from", michelson_pair(address, "to", amt, "value"), "");
type approveParams = michelson_pair(trusted, "spender", amt, "value");
type balanceParams = michelson_pair(address, "owner", contract(amt), "");
type allowanceParams = michelson_pair(michelson_pair(address, "owner", trusted, "spender"), "", contract(amt), "");
type totalSupplyParams = (unit, contract(amt));

// Valid entry points 
type entryAction =
  | Transfer (transferParams)
  | Approve (approveParams)
  | GetBalance (balanceParams)
  | GetAllowance (allowanceParams)
  | GetTotalSupply (totalSupplyParams)

// Helper function to get account 
let getAccount = (addr: address, s: storage): account => {
  switch (Map.find_opt(addr, s.ledger)){
    | None => { balance: 0n, allowances : (Map.empty: map (address, amt)) }
    | Some (acct) => acct
  }
}

// Helper function to get allowance for an account 
let getAllowance = (ownerAccount: account, spender: address, s: storage): amt => {
  switch (Map.find_opt(spender, ownerAccount.allowances)) {
    | None => 0n
    | Some (amt) => amt
  }
}

// Helper function to verify transfer is allowed for a certain address
let isTransferAllowed = (from_: address, value: nat, s: storage): bool => {
  if (Tezos.sender != from_) {
    // Checking if the sender is allowed to spend in name of from_
    switch (Big_map.find_opt(from_, s.ledger)){
      | None => false
      | Some (acc) => {
          switch (Map.find_opt(Tezos.sender, acc.allowances)){
          | None => false
          | Some (allowanceAmount) => allowanceAmount >= value
        }
      }
    }
  } else {
    true;
  }
}

// Transfer token to another account 
let transfer = ((params, s): (transferParams, storage)): return => {
  let from_ = params[0];
  let to_ = params[1][0];
  let value = params[1][1];
  // Forbidden transaction to self
  if (from_ == to_){
    failwith("InvalidSelfToSelfTransfer"): return ;
  } else {
    // Retrieve sender account from storage 
    let senderAccount: account = getAccount(from_, s);

    // Balance check 
    if (senderAccount.balance < value) {
      failwith("NotEnoughBalance"): return ;
    } else {
      // Check this address can spend the tokens 
      if (!isTransferAllowed(from_, value, s)) {
        failwith("NotEnoughAllowance"): return ;
      } else {
        // Update spender's allowance
        let newAllowance = switch(Map.find_opt(Tezos.sender, senderAccount.allowances)){
          | None => None: option (nat)
          | Some (allowance) => Some (abs(allowance - value))
        };
        // Update sender's balance in ledger
        let ledger1 = 
          Big_map.update(from_, 
                        Some ({...senderAccount, 
                          balance: abs(senderAccount.balance - value), 
                          allowances: Map.update(Tezos.sender, newAllowance, senderAccount.allowances)}), 
                        s.ledger);

        // Create or get destination account
        let destAccount: account = getAccount(to_, s);

        // Update destination balance
        let ledger2 = 
          Big_map.update(to_, 
                        Some ({...destAccount, balance: destAccount.balance + value}), 
                        ledger1);

        // Return new storage
        ([]: list (operation), {...s, ledger: ledger2});
      }
    }
  }
}
  
// Approve an amount to be spent by another address in the name of the sender
let approve = ((params, s): (approveParams, storage)) : return => {
  let (spender, value) = params;
  if (spender == Tezos.sender) {
    failwith("InvalidSelfToSelfApproval"): return ;
  } else {
    // Create or get sender account
    let senderAccount: account = getAccount(Tezos.sender, s);

    // Get current spender allowance
    let spenderAllowance: amt = getAllowance(senderAccount, spender, s);

    // Prevent an approve method attack vector
    if (spenderAllowance > 0n && value > 0n) {
      failwith("UnsafeAllowanceChange"): return ;
    } else {
      // Set spender allowance
      let newAllowances = Map.update(spender, Some (value), senderAccount.allowances);

      // Update storage
      ([]: list (operation), 
      {...s, ledger: 
            Big_map.update(Tezos.sender, 
                            Some ({...senderAccount, allowances: newAllowances}), 
                            s.ledger)});
    }
  }
}

// View function that forwards the balance of source to a contract
let getBalance = ((params, s): (balanceParams, storage)): return => {
  let (owner, contr) = params;
  let ownerAccount: account = getAccount(owner, s);

  ([Tezos.transaction(ownerAccount.balance, 0tz, contr)]: list (operation), s);
}

// View function that forwards the allowance amt of spender in the name of tokenOwner to a contract 
let getAllowance = ((params, s): (allowanceParams, storage)): return => {
  let owner: address = params[0][0];
  let spender: address = params[0][1];
  let contr: contract (amt) = params[1];

  let ownerAccount: account = getAccount(owner, s);
  let spenderAllowance: amt = getAllowance(ownerAccount, spender, s);

  ([Tezos.transaction(spenderAllowance, 0tz, contr)]: list (operation), s);
}

// View function that forwards the totalSupply to a contract 
let getTotalSupply = ((contr, s): (contract (amt), storage)): return => {
  ([Tezos.transaction(s.totalSupply, 0tz, contr)]: list (operation), s);
}

// Main entrypoint 
let main = ((action, s): (entryAction, storage)): return => {
  if(Tezos.amount > 0tz) {
    failwith("NoAmountAllowed"): return ;
  } else {
    switch (action) {
      | Transfer(params) => transfer((params, s))
      | Approve(params) => approve((params, s))
      | GetBalance(params) => getBalance((params, s))
      | GetAllowance(params) => getAllowance((params, s))
      | GetTotalSupply(params) => getTotalSupply((params[1], s))
    };
  }
}