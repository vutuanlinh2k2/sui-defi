# SUI Move AMM (Inspired by Uniswap V2)

## Introduction

This project implements an Automated Market Maker (AMM) on the SUI blockchain using Move language, inspired by Uniswap V2.

## Features

- **Token Pair Creation**: Create liquidity pools between any two tokens
- **Liquidity Provision**: Add and remove liquidity with slippage protection
- **Swapping**: Exchange tokens with minimal slippage
  - Swap exact input for variable output
  - Swap variable input for exact output
- **Fee Collection**: 0.3% trading fee with protocol fee mechanism
- **Price Oracle**: Time-weighted average price (TWAP) functionality
- **Minimum Liquidity**: Locked liquidity to prevent pool draining
- **Canonical Ordering**: Automatic token pair ordering for consistency
- **Admin Controls**: Versioning and fee management capabilities
- **Comprehensive Testing**: Extensive test suite for most functionalities

## Architecture

The project is structured into several modules:
- `amm`: Main entry point with user-facing functions
- `pair`: Core liquidity pool implementation
- `registry`: Pair registration and admin functionality
- `decimal`: Precise decimal arithmetic operations
- `utils`: Helper functions for token ordering
- `constants`: Version management
