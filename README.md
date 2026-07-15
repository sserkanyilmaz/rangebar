# viemora

A macOS menu bar app for monitoring liquidity positions.

## Features

- Meteora/Solana position tracking through LPAgent
- Uniswap V3 and V4 position tracking for EVM wallets
- Multiple locally stored wallets
- Configurable Meteora links
- Direct links to Uniswap position pages
- Automatic refresh

## Supported platforms and protocols

### Solana

- **Meteora DLMM** positions
- **LPAgent** for position values, fees, PnL, and strategy data
- **Hawksight / HawkFi** for additional positions, real bin distributions, token metadata, claimed fees, invested capital, and economic PnL
- LPAgent and Hawksight results are merged and deduplicated by position address

### EVM

- **Uniswap V3** positions
- **Uniswap V4** positions
- Configured chain mappings: Ethereum, Unichain, Base, Arbitrum, Optimism, Polygon, BNB Chain, Avalanche, Celo, Linea, zkSync, World Chain, Zora, Blast, and Robinhood Chain
- **DexScreener** enrichment, when available for the chain and pool, for current market cap and estimated lower/current/upper market-cap ranges
- Direct links to position pages on the Uniswap app

## Local configuration

Wallets are stored locally in `UserDefaults`.

The LPAgent API key is entered in Settings and stored only in the app container's local `.env` file. Local `.env` files are excluded from Git.

Uniswap positions use Uniswap's interface gateway. This is an internal endpoint and may change without notice.

## Build

Open `viemora.xcodeproj` in Xcode and build the `viemora` scheme.

## License

MIT
