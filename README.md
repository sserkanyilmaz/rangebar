# viemora

A macOS menu bar app for monitoring liquidity positions.

## Features

- Meteora/Solana position tracking through LPAgent
- Uniswap V3 and V4 position tracking for EVM wallets
- Multiple locally stored wallets
- Configurable Meteora links
- Direct links to Uniswap position pages
- Automatic refresh

## Local configuration

Wallets are stored locally in `UserDefaults`.

The LPAgent API key is entered in Settings and stored only in the app container's local `.env` file. Local `.env` files are excluded from Git.

Uniswap positions use Uniswap's interface gateway. This is an internal endpoint and may change without notice.

## Build

Open `viemora.xcodeproj` in Xcode and build the `viemora` scheme.

## License

MIT
