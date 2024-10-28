# SPL

The SPL (Sports Prediction League) Smart Contract manages the on-chain functionalities for the Sports Prediction League, enabling decentralized and transparent user engagement with sports predictions. The contract registers matches, accepts user predictions, and records match results on the starknet blockchain.

## Features

- **Match Registration**: Allows the backend to register upcoming matches on-chain, making them available for user predictions.
- **Prediction Submission**: Users submit predictions for registered matches, which are recorded immutably on the blockchain.
- **Result Recording**: Final results are stored on-chain, allowing users to verify prediction outcomes in real-time.

## Tech Stack

- **Cairo**: Programming language for starknet smart contracts.
- **Starknet**: Ethereum Layer 2 solution providing scalable and efficient transactions.

## Security

- **Authorized Access for Result Recording**: Only specific addresses are authorized to record match results, ensuring verified data.
