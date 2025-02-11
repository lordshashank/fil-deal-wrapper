# Wrapped Deal – A Trustless Automated Payment CLI for Filecoin Deals

This repository provides a command-line interface (CLI) called **Wrapped Deal** that aims to offer trustless automated payments to Storage Providers (SPs) for Filecoin deal services. By using the **MarketDealWrapper** smart contract, clients can automate fund transfers to SPs whenever a deal is made, eliminating the need for manual payment arrangements.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Architecture Overview](#architecture-overview)
3. [Prerequisites](#prerequisites)
4. [Setup](#setup)
   1. [Clone the Repository](#1-clone-the-repository)
   2. [Adjust the go.mod Replacement](#2-adjust-the-go-mod-replacement)
   3. [Build & Deploy the Smart Contract](#3-build--deploy-the-smart-contract)
   4. [Build the CLI](#4-build-the-cli)
   5. [Running the CLI](#5-running-the-cli)
5. [CLI Usage Guide](#cli-usage-guide)
   1. [fil](#1-fil)
   2. [write-contract](#2-write-contract)
   3. [read-contract](#3-read-contract)
6. [Deal Making Flow Using Wrapped Deal](#deal-making-flow-using-wrapped-deal)
7. [IMPORTANT NOTES](#important-notes)
8. [Additional Resources](#additional-resources)

---

## Introduction

**Wrapped Deal** is designed to streamline and secure the payment process between Filecoin clients and Storage Providers:

- Offers an on-chain mechanism to handle payments, ensuring trustless transactions.
- Provides a set of commands to read and write data to the **MarketDealWrapper** smart contract.
- Integrates with the Filecoin network using tools such as [Foundry](https://book.getfoundry.sh/) and [Boost](https://boost.filecoin.io/docs).

---

## Architecture Overview

The **Wrapped Deal** CLI interacts with the **MarketDealWrapper** smart contract to automate payments for Filecoin deals. The flow looks like this:

```mermaid
graph TD
    A[Deploy MarketDealWrapper Contract] --> B[Add Storage Provider with Payment Token and Address]
    B --> C[Whitelist f1 Address in Contract]
    C --> D[Approve and Add Tokens for SP Payment]
    D --> E[Make Boost Deal using Whitelisted Address]

    subgraph Market_Actor_Calls[Market Actor Callbacks]
        subgraph Notify[deal_notify]
            F[Initialize Payment Schedule to SP]
        end
        subgraph Auth[authenticate_message]
            H[Verify Signature]
        end

    end

    E --> Market_Actor_Calls
    Market_Actor_Calls --> J[SP Requests Payment Withdrawal]
    J --> K{Check if Deal is Live}
    K -->|Yes| L[Release Payment Based on Epochs Passed]
    K -->|No| M[Pay Only for Maintained Period]

    style A fill:#e1f5fe
    style E fill:#e8f5e9
    style Market_Actor_Calls fill:#fff3e0, color:#000000
    style Auth fill:#ffe0b2, color:#000000
    style Notify fill:#ffe0b2, color:#000000
    style K fill:#fce4ec
```

## Prerequisites

1. **Foundry**

   - Used to build and deploy the MarketDealWrapper contract.
   - Install via:
     ```bash
     curl -L https://foundry.paradigm.xyz | bash
     foundryup
     ```
   - Refer to the official [Foundry documentation](https://book.getfoundry.sh/) for detailed instructions.

2. **Boost**

   - Allows you to make deals on the Filecoin network.
   - Refer to [Boost’s official documentation](https://boost.filecoin.io/docs) for setup and usage details.

3. **Boost Wallet**

   - Ensure you have a funded wallet set in boost to make deals on the Filecoin network.
   - If not set you can set it with the following command:
     ```bash
     boost wallet new
     ```
   - Refer to the [Boost Wallet documentation](https://boost.filecoin.io/docs/wallet) for more information.

4. **Go (1.22.x recommended)**
   - Verify with:
     ```bash
     go version
     ```
   - If needed, install or update from [golang.org](https://golang.org/dl/).

---

## Setup

### 1. Clone the Repository

Use Git to clone this repository:

```bash
git clone https://github.com/your-organization/fil-deal-wrapper.git
cd fil-deal-wrapper
```

### 2. Adjust the go.mod Replacement

Inside the project’s go.mod file, a **replace** directive is used to point to a local build of filecoin-ffi

Replace the path with the local path on your machine where **filecoin-ffi** is located. For example:

```go
replace github.com/filecoin-project/filecoin-ffi => /path/to/your/boost/extern/filecoin-ffi
```

### 3. Build & Deploy the Smart Contract

1. Enter the contracts directory (or wherever your Foundry project is located):

   ```bash
   cd contracts
   ```

2. Build the **MarketDealWrapper** contract:

   ```bash
   forge build
   ```

3. Deploy the contract to a desired network (e.g., Anvil, testnet, or mainnet):

   ```bash
   forge create --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY> src/MarketDealWrapper.sol:MarketDealWrapper
   ```

   Make sure to replace `<YOUR_RPC_URL>` and `<YOUR_PRIVATE_KEY>` with actual values.

4. Note the contract address displayed after deployment, as you will need it to interact with the contract using the CLI.

### 4. Build the CLI

1. Return to the root directory of the project:

   ```bash
   cd ..
   ```

2. Set the environment variable for CLI to avoid putting some flags every time:

- `PRIVATE_KEY`
- `RPC_URL`
- `FULL_NODE_API_INFO` - https://api.calibration.node.glif.io/rpc/v1 for calibration network

If you want to make local deals directly with files in your environment you will need:

- `LIGHTHOUSE_API_KEY`

3. Build the **Wrapped Deal** CLI:

   ```bash
   go build -o wrappedeal
   ```

This produces an executable called **wrappedeal** in your current directory.

### 5. Running the CLI

Once built, run the CLI with:

```bash
./wrappedeal help
```

OR

```bash
wrappedeal help
```

---

### CLI Usage Guide

Below are the main commands and subcommands available in **wrappedeal**, along with examples on how to use them. Ensure that all flags are specified before the parameters. Do see **IMPORTANT NOTES** at the end to avoid common pitfalls.

---

## 1. **fil**

Use `fil` for Filecoin-related tasks.

```bash
wrappedeal fil [subcommand] [flags]
```

### Subcommands

1. **deal**  
   Make an online deal with a CAR file.

   ```bash
   wrappedeal fil deal \
     --http-url "<HTTP_URL>" \
     --car-size <SIZE> \
     --provider "<SP_ADDRESS>" \
     --commp "<COMM_P>" \
     --piece-size <PIECE_SIZE> \
     --payload-cid "<CID>" \
     --contract "<CONTRACT_ADDRESS>"
   ```

2. **local-deal**  
   Make a deal from a local file or folder.

   ```bash
   wrappedeal fil local-deal \
     --path "<FILE_OR_FOLDER_PATH>" \
     --provider "<SP_ADDRESS>" \
     --contract "<CONTRACT_ADDRESS>"
     --lighthouse true # optional
   ```

3. **offline-deal**  
   Make an offline deal (the CAR is provided out-of-band).

   ```bash
   wrappedeal fil offline-deal \
     --provider "<SP_ADDRESS>" \
     --commp "<COMM_P>" \
     --piece-size <PIECE_SIZE> \
     --payload-cid "<CID>" \
     --contract "<CONTRACT_ADDRESS>"
   ```

4. **get-eth-addr**  
   Get the Ethereum address corresponding to a Filecoin address.

   ```bash
   wrappedeal fil get-eth-addr \
     --filecoin-addr "<FILECOIN_ADDRESS>" \
   ```

5. **get-actor-id**  
   Retrieve the Actor ID from a Filecoin address.

   ```bash
   wrappedeal fil get-actor-id \
     --filecoin-addr "<FILECOIN_ADDRESS>" \
   ```

---

## 2. **write-contract**

Use `write-contract` to send write transactions to the MarketDealWrapper contract.

```bash
wrappedeal write-contract [subcommand] [flags] [parameters]
```

### Subcommands

1. **add-sp**  
   Add a storage provider to the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract add-sp \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     --actor-id <ACTOR_ID> \
     --eth-addr "<ETH_ADDRESS>" \
     --token "<TOKEN_ADDRESS>" \
     --price-per-tb-per-month <PRICE>
   ```

2. **update-sp**  
   Update a storage provider in the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract update-sp \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     --actor-id <ACTOR_ID> \
     --eth-addr "<NEW_ETH_ADDRESS>" \
     --token "<NEW_TOKEN_ADDRESS>" \
     --price-per-tb-per-month <NEW_PRICE>
   ```

3. **add-to-whitelist**  
   Add an Actor ID to the whitelist in the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract add-to-whitelist \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     <ACTOR_ID>
   ```

4. **remove-from-whitelist**  
   Remove an Actor ID from the whitelist in the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract remove-from-whitelist \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     <ACTOR_ID>
   ```

5. **add-funds**  
   Add native funds to the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract add-funds \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<AMOUNT>"
   ```

6. **withdraw-funds**  
   Withdraw native funds from the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract withdraw-funds \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<AMOUNT>"
   ```

7. **approve-erc20**  
   Approve the MarketDealWrapper contract to spend ERC20 tokens.

   ```bash
   wrappedeal write-contract approve-erc20 \
     --contract-address "<TOKEN_CONTRACT_ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<SPENDER_ADDRESS>" "<AMOUNT>"
   ```

8. **add-funds-erc20**  
   Add ERC20 tokens to the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract add-funds-erc20 \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<TOKEN_ADDRESS>" "<AMOUNT>"
   ```

9. **withdraw-funds-erc20**  
   Withdraw ERC20 tokens from the MarketDealWrapper contract.

   ```bash
   wrappedeal write-contract withdraw-funds-erc20 \
     --contract-address "<ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<TOKEN_ADDRESS>" "<AMOUNT>"
   ```

10. **withdraw-sp-funds-by-token**  
    Withdraw total SP funds by ERC20 token from the MarketDealWrapper contract.

    ```bash
    wrappedeal write-contract withdraw-sp-funds-by-token \
      --contract-address "<ADDRESS>" \
      --private-key "<PRIVATE_KEY>" \
      --abi-path "<ABI_PATH>" \
      --rpc-url "<RPC_URL>" \
      "<TOKEN_ADDRESS>"
    ```

11. **withdraw-sp-funds-for-deal**  
    Withdraw SP funds for a specific deal from the MarketDealWrapper contract.

    ```bash
    wrappedeal write-contract withdraw-sp-funds-for-deal \
      --contract-address "<ADDRESS>" \
      --private-key "<PRIVATE_KEY>" \
      --abi-path "<ABI_PATH>" \
      --rpc-url "<RPC_URL>" \
      "<DEAL_ID>"
    ```

12. **withdraw-sp-funds-for-terminated-deal**  
    Withdraw SP funds for a terminated deal from the MarketDealWrapper contract.

    ```bash
    wrappedeal write-contract withdraw-sp-funds-for-terminated-deal \
      --contract-address "<ADDRESS>" \
      --private-key "<PRIVATE_KEY>" \
      --abi-path "<ABI_PATH>" \
      --rpc-url "<RPC_URL>" \
      "<DEAL_ID>"
    ```

---

## 3. **read-contract**

Use `read-contract` to read data from the MarketDealWrapper contract.

```bash
wrappedeal read-contract [subcommand] [flags] [parameters]
```

### Subcommands

1. **get-sp-id**  
   Get Storage Provider address by Actor ID.

   ```bash
   wrappedeal read-contract get-sp-id \
     --contract-address "<ADDRESS>" \
     <actor-id>
   ```

2. **get-deals-from-miner-id**  
   Retrieve deal IDs associated with a given miner ID.

   ```bash
   wrappedeal read-contract get-deals-from-miner-id \
     --contract-address "<ADDRESS>" \
     <miner-id>
   ```

3. **is-whitelisted**  
   Check if an Actor ID is whitelisted.

   ```bash
   wrappedeal read-contract is-whitelisted \
     --contract-address "<ADDRESS>" \
     <ACTOR_ID>
   ```

4. **get-sp-funds-for-deal**  
   Retrieve the currently claimable SP funds for a specific deal.

   ```bash
   wrappedeal read-contract get-sp-funds-for-deal \
     --contract-address "<ADDRESS>" \
     <deal-id>
   ```

5. **get-token-funds-for-sp**  
   Retrieve the currently claimable SP funds for a specific ERC20 token and actor ID.

   ```bash
   wrappedeal read-contract get-token-funds-for-sp \
     --contract-address "<ADDRESS>" \
     <token> <actor-id>
   ```

---

## Deal Making Flow Using Wrapped Deal

Follow the steps below to create and manage a Filecoin deal using **Wrapped Deal**. Each step includes a description of the action being performed along with the corresponding CLI command. Ensure that all flags are specified before the parameters.

1. **Deploy the `MarketDealWrapper` Contract**

   Before initiating any deals, ensure that the `MarketDealWrapper` smart contract is deployed to your desired network (e.g., Anvil, testnet, or mainnet). This contract will handle the automated payments to Storage Providers (SPs). [[Deployed Contract](https://calibration.filfox.info/en/message/bafy2bzacedule3afprmjpp3q7v5a2zwjolqyfjqlrjxkanysezvakasjjx4vy)]

   ```bash
   forge create --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY> src/MarketDealWrapper.sol:MarketDealWrapper
   ```

2. **Add a Storage Provider (SP)**

   Register a Storage Provider with the `MarketDealWrapper` contract. This step associates the SP's actor ID, Ethereum address, ERC20 token, and pricing information with the contract, allowing clients to make deals with this SP. [[Sp add trans](https://calibration.filfox.info/en/message/bafy2bzaceboj5grhqpenvbtzyw5dn7qoduh4dkcruo7hs62byo7tabnyi4vy4)]

   ```bash
   wrappedeal write-contract add-sp \
     --contract-address "<CONTRACT_ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     --actor-id <ACTOR_ID> \
     --eth-addr "<ETH_ADDRESS>" \
     --token "<TOKEN_ADDRESS>" \
     --price-per-tb-per-month <PRICE>
   ```

3. **Get Actor ID of your Filecoin address**

   To retrieve the actor ID from your Filecoin address, you can run:

   ```bash
   wrappedeal fil get-actor-id \
     --filecoin-addr "<FILECOIN_ADDRESS>" \
   ```

4. **Add the Actor ID to Whitelist**

   Whitelist the actor ID(remove `t0` or `f0` prefix) in the MarketDealWrapper contract:

   ```bash
   wrappedeal write-contract add-to-whitelist \
     --contract-address "<CONTRACT_ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     <ACTOR_ID>
   ```

5. **Approve ERC20 Tokens for the Contract**

   Approve the `MarketDealWrapper` contract to spend a specified amount of your ERC20 tokens. This is necessary to facilitate the transfer of funds from your wallet to the contract for deal payments.
   You can use USDFC stablecoin (Get address from [here](https://docs.secured.finance/stablecoin-protocol-guide/technical-resources)) for testing.

   ```bash
   wrappedeal write-contract approve-erc20 \
     --contract-address "<TOKEN_CONTRACT_ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<CONTRACT_ADDRESS>" "<AMOUNT>"
   ```

6. **Add ERC20 Funds to the Contract**

   Transfer approved ERC20 tokens to the `MarketDealWrapper` contract. These funds will be used to automatically pay the Storage Provider for the deals made. [[USDFC add trans](https://calibration.filfox.info/en/message/bafy2bzacebykgvm5psapxwzapk3xwtzzr5lb2tcx3hopufikdcsw4v344nb5o)]

   ```bash
   wrappedeal write-contract add-funds-erc20 \
     --contract-address "<CONTRACT_ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<TOKEN_ADDRESS>" "<AMOUNT>"
   ```

7. **Make a Local Deal with the SP**

   Create a local deal with the registered Storage Provider. This command uploads the specified file or folder, associates it with the SP, and records the deal in the contract. The `verified` tag is set to `true` by default. You can get DataCap in Calibnet for your contract from [here](https://faucet.calibnet.chainsafe-fil.io/). [[on-chain deal](https://calibration.filfox.info/en/deal/209296)]

   ```bash
   wrappedeal fil local-deal \
     --path "<FILE_OR_FOLDER_PATH>" \
     --provider "<SP_ADDRESS>" \
     --contract "<CONTRACT_ADDRESS>"
   ```

   **_Client Flow Complete_**

8. **Storage Provider Withdraws Funds for a Deal**

   The registered Storage Provider can withdraw funds for a specific deal at any time. Funds are vested and become available as per the epoch schedule defined in the contract. [[Sp's address claims USDFC](https://calibration.filfox.info/en/message/bafy2bzacebxhlbr2o47jmsckxze7vwex4rmnnn4pvqcds3yq2zv3beyczlajm)]

   ```bash
   wrappedeal write-contract withdraw-sp-funds-for-deal \
     --contract-address "<CONTRACT_ADDRESS>" \
     --private-key "<PRIVATE_KEY>" \
     --abi-path "<ABI_PATH>" \
     --rpc-url "<RPC_URL>" \
     "<DEAL_ID>"
   ```

   _Note:_

- Funds are vested according to the epoch schedule, ensuring timely and automated payments to the Storage Provider.
- The SP can withdraw funds for a terminated deal using the `withdraw-sp-funds-for-terminated-deal` command.
- Client has admin rights to add or remove SPs, whitelist addresses, and manage contract funds.

---

## IMPORTANT NOTES

1. **RPC URL and Private Key**

   - Ensure that the RPC URL and private key are set and sourced from env to avoid passing it everytime.
   - The private key should be kept secure and not shared with others.

2. **ABI Path**

   - The ABI path should point to the MarketDealWrapper contract ABI file.
   - Ensure that the ABI file has abi in following format
     ```json
     {
         "abi": <ABI>
     }
     ```

3. **Wallet Type for `get-eth-addr`**

   - The default wallet should be `secp256k1` as we can derive eth-address for that only, `bls` is not supported.

4. **Build Issues**

   - If you encounter build issues, ensure that the go.mod file is correctly set up with boost path, etc as mentioned in the prerequisites.
   - Verify that the correct version of Go is installed.

5. **Actor ID initialization**

   - Ensure that the Actor ID is initialized correctly for your addresses you are using. You may need to fund the smart contract or EOA with small amounts of FIL to initialize the Actor.

## Additional Resources

- **Foundry Docs:** [https://book.getfoundry.sh/](https://book.getfoundry.sh/)
- **Boost Docs:** [https://boost.filecoin.io/docs](https://boost.filecoin.io/docs)
- **Go Modules:** [https://go.dev/doc/modules](https://go.dev/doc/modules)
- **Faucet:** [https://faucet.calibnet.chainsafe-fil.io/](https://faucet.calibnet.chainsafe-fil.io/)

---

**Enjoy using Wrapped Deal to streamline and automate your Filecoin deal payments!**
