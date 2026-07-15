import Foundation

struct WalletConfig: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var address: String
    var linkMode: MeteoraLinkMode
    var network: WalletNetwork?

    init(id: UUID = UUID(), name: String, address: String, linkMode: MeteoraLinkMode, network: WalletNetwork = .solana) {
        self.id = id
        self.name = name
        self.address = address
        self.linkMode = linkMode
        self.network = network
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Wallet" : name
    }

    // Existing saved wallets predate the network field and are Solana wallets.
    var resolvedNetwork: WalletNetwork {
        network ?? (address.lowercased().hasPrefix("0x") ? .evm : .solana)
    }
}

enum WalletNetwork: String, CaseIterable, Codable, Identifiable {
    case solana
    case evm

    var id: String { rawValue }
    var title: String { self == .solana ? "Solana" : "EVM" }
}

enum MeteoraLinkMode: String, CaseIterable, Codable, Identifiable {
    case edge
    case app
    case meteora

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edge: return "Edge"
        case .app: return "App"
        case .meteora: return "Meteora"
        }
    }

    var baseURL: String {
        switch self {
        case .edge: return "https://edge.meteora.ag/dlmm"
        case .app: return "https://app.meteora.ag/dlmm"
        case .meteora: return "https://www.meteora.ag/dlmm"
        }
    }
}

struct UniswapPosition: Identifiable {
    let chainId: Int
    let protocolVersion: String
    let tokenId: String
    let poolId: String
    let token0: UniswapToken
    let token1: UniswapToken
    let tickLower: Int
    let tickUpper: Int
    let currentTick: Int
    let amount0: Double
    let amount1: Double
    let feeAmount0: Double
    let feeAmount1: Double
    let valueUsd: Double
    let uncollectedFeesUsd: Double
    let apr: Double?
    let status: String
    let marketData: UniswapMarketData?

    var id: String { "\(chainId)-\(protocolVersion)-\(tokenId)" }
    var pairName: String { "\(token0.symbol)/\(token1.symbol)" }
    var inRange: Bool { status == "POSITION_STATUS_IN_RANGE" }

    var currentRangePercent: Double {
        guard tickUpper > tickLower else { return 0.5 }
        return Double(currentTick - tickLower) / Double(tickUpper - tickLower)
    }

    var marketCapRangePercent: Double {
        guard let marketData else { return currentRangePercent }
        return marketData.baseTokenAddress.lowercased() == token1.address.lowercased()
            ? 1 - currentRangePercent
            : currentRangePercent
    }

    var marketCapRange: (lower: Double, current: Double, upper: Double)? {
        guard let marketData, marketData.marketCap > 0 else { return nil }
        let base = marketData.baseTokenAddress.lowercased()
        let direction: Double
        if base == token0.address.lowercased() {
            direction = 1
        } else if base == token1.address.lowercased() {
            direction = -1
        } else {
            return nil
        }

        let lowerRatio = pow(1.0001, Double(tickLower - currentTick) * direction)
        let upperRatio = pow(1.0001, Double(tickUpper - currentTick) * direction)
        let a = marketData.marketCap * lowerRatio
        let b = marketData.marketCap * upperRatio
        return (min(a, b), marketData.marketCap, max(a, b))
    }

    func withMarketData(_ data: UniswapMarketData?) -> UniswapPosition {
        UniswapPosition(
            chainId: chainId, protocolVersion: protocolVersion, tokenId: tokenId, poolId: poolId,
            token0: token0, token1: token1, tickLower: tickLower, tickUpper: tickUpper,
            currentTick: currentTick, amount0: amount0, amount1: amount1,
            feeAmount0: feeAmount0, feeAmount1: feeAmount1, valueUsd: valueUsd,
            uncollectedFeesUsd: uncollectedFeesUsd, apr: apr, status: status, marketData: data
        )
    }

    var appURL: URL? {
        guard let chain = UniswapChain.slug(for: chainId) else { return nil }
        let version: String
        switch protocolVersion {
        case "PROTOCOL_VERSION_V3": version = "v3"
        case "PROTOCOL_VERSION_V4": version = "v4"
        default: return nil
        }
        return URL(string: "https://app.uniswap.org/positions/\(version)/\(chain)/\(tokenId)")
    }
}

struct UniswapMarketData {
    let baseTokenAddress: String
    let marketCap: Double
    let priceUsd: Double?
    let liquidityUsd: Double?
}

struct UniswapToken: Codable {
    let chainId: Int
    let address: String
    let symbol: String
    let decimals: Int
    let name: String
}

enum UniswapChain {
    static func slug(for chainId: Int) -> String? {
        [
            1: "ethereum", 10: "optimism", 56: "bnb", 130: "unichain",
            137: "polygon", 324: "zksync", 480: "worldchain", 4663: "robinhood",
            8453: "base", 42161: "arbitrum", 42220: "celo", 43114: "avalanche",
            59144: "linea", 7777777: "zora", 81457: "blast"
        ][chainId]
    }
}

struct Position: Identifiable {
    let id: String
    let pairName: String
    let tokenName0: String
    let tokenName1: String
    let value: Double
    let inRange: Bool
    let strategyType: String
    let priceRange: [Double]
    let range: [Int]
    let tickLower: Int
    let tickUpper: Int
    // Total uncollected fee in USD
    let pool: String
    let unCollectedFee: Double
    // Per-token amounts
    let amount0: Double       // e.g. 82.47 HYPE
    let amount1: Double       // e.g. 31.95 SOL
    let feeAmount0: Double    // e.g. 0.009 HYPE
    let feeAmount1: Double    // e.g. 0.001 SOL
    let logo0: String?
    let logo1: String?
    let bins: [BinInfo]
    let pnl: PnL
    let valueNative: Double
    let investedValue: Double?
    let claimedFee: Double?

    var activeBin: Int {
        range.count >= 3 ? range[2] : 0
    }

    var activeBinPercent: Double {
        let total = tickUpper - tickLower
        guard total > 0 else { return 0.5 }
        return Double(activeBin - tickLower) / Double(total)
    }
}

struct PnL: Codable {
    let value: Double
    let percent: Double
    let valueNative: Double?
    let percentNative: Double?
}

struct BinInfo: Codable {
    let binId: Int
    let binXAmount: String?
    let binYAmount: String?
    let positionXAmount: String?
    let positionYAmount: String?
    let positionLiquidity: String?
}

struct CurrentAmounts: Codable {
    let amount0Adjusted: Double?
    let amount1Adjusted: Double?
}

// DTO handles the messy JSON types
struct PositionDTO: Codable {
    let id: String?
    let tokenId: String?
    let pairName: String
    let tokenName0: String
    let tokenName1: String
    let value: Double?
    let inRange: Bool
    let strategyType: String?
    let priceRange: [Double]?
    let range: [Int]?
    let tickLower: Int?
    let tickUpper: Int?
    let pool: String?
    let unCollectedFee: FlexibleDouble?
    let unCollectedFee0: Double?
    let unCollectedFee1: Double?
    let current: CurrentAmounts?
    let logo0: String?
    let logo1: String?
    let bins: [BinInfo]?
    let pnl: PnL?
    let inputNative: Double?

    private var resolvedStrategyType: String {
        let trimmed = strategyType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Manual" : trimmed
    }

    func toPosition() -> Position {
        Position(
            id: id ?? tokenId ?? UUID().uuidString,
            pairName: pairName,
            tokenName0: tokenName0,
            tokenName1: tokenName1,
            value: value ?? 0,
            inRange: inRange,
            strategyType: resolvedStrategyType,
            priceRange: priceRange ?? [],
            range: range ?? [],
            tickLower: tickLower ?? 0,
            tickUpper: tickUpper ?? 0,
            pool: pool ?? "",
            unCollectedFee: unCollectedFee?.doubleValue ?? 0,
            amount0: current?.amount0Adjusted ?? 0,
            amount1: current?.amount1Adjusted ?? 0,
            feeAmount0: unCollectedFee0 ?? 0,
            feeAmount1: unCollectedFee1 ?? 0,
            logo0: logo0,
            logo1: logo1,
            bins: bins ?? [],
            pnl: pnl ?? PnL(value: 0, percent: 0, valueNative: nil, percentNative: nil),
            valueNative: (inputNative ?? 0) + (pnl?.valueNative ?? 0),
            investedValue: nil,
            claimedFee: nil
        )
    }
}

struct PositionDTOResponse: Codable {
    let status: String
    let count: Int
    let data: [PositionDTO]
}

// Handles fields that come as either String or Double in the API
struct FlexibleDouble: Codable {
    let doubleValue: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            doubleValue = d
        } else if let s = try? container.decode(String.self), let d = Double(s) {
            doubleValue = d
        } else {
            doubleValue = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(doubleValue)
    }
}
