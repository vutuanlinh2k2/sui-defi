# Prize Savings on SUI

A decentralized savings protocol built on Sui blockchain that allows users to earn prizes while saving their assets. This project is inspired by [PoolTogether](https://pooltogether.com/), implementing a similar prize savings mechanism with Time-Weighted Average Balance (TWAB) for fair prize distribution.

## Overview

This is a no-loss savings protocol where users deposit their assets into a pool, which then will be deposited to a protocol to earn yield. The yield generated from these deposits is used as prizes to random winners, while ensuring users can withdraw their original deposits at any time.

## Key Features

- No-loss savings: Users can withdraw their original deposits at any time
- Prize distribution: Regular prize draws for active participants
- Transparent: All operations and prize distributions are on-chain
- Decentralized: Built on Sui blockchain for security and transparency
- TWAB-based: Fair prize distribution using Time-Weighted Average Balance

## How It Works

1. Users deposit their assets into the prize pool
2. The protocol simulates yield generation through a simulated DeFi protocol (in real scenario this can be SuiLend, Navi Protocol, etc.)
3. When it's time for a new draw, a prize pool will be created and use the yield as rewards for winners
4. Winners are selected randomly and fairly using TWAB (Time-Weighted Average Balance) to ensure fair chances based on deposit duration and amount
5. Users can withdraw their deposits at any time

## Files

- `protocol.move`: Simulates a yield-generating protocol that earns yields for depositors
- `pool.move`: Manages the main prize pool where users deposit their assets
- `prize_pool_config.move`: Configures prize pool parameters
- `prize_pool.move`: Handles prize distribution and winner selection
- `twab_controller.move`: Manages Time-Weighted Average Balance calculations for the pool and each participant
- `twab_info.move`: Stores TWAB Info for a single entity
- `registry.move`: Maintains registry of pools and their configurations

## Additional Info

### Prize Pool and Deadlines

- Each prize pool has an expiration timeframe (in days)
- Winners must claim their prizes before the deadline
- Unclaimed prizes are automatically rolled over to the next draw
- This ensures no prizes are lost and maintains the protocol's efficiency

### Time-Weighted Average Balance (TWAB)

TWAB is a crucial mechanism that ensures fair prize distribution by:

- Tracking the average balance of each user over time
- Considering both the amount deposited and the duration of the deposit
- Calculating a user's chance to win based on their TWAB relative to the total pool TWAB
- Preventing manipulation by requiring consistent participation
- Higher TWAB = Higher chance of winning
