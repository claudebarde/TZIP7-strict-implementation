# Strict implementation of the TZIP7 proposal in ReasonLigo

The implementation follows the guidelines for Michelson implementation as close as possible.

Only the entrypoints referenced in the proposal are implemented in the contract.

The test suite verifies that the `approve` and `transfer` entrypoints work as expected by deploying the contract using Truffle and calling the entrypoints with different parameters.
