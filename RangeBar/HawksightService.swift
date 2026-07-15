import Foundation

final class HawksightService {
    static let shared = HawksightService()

    func fetchOpenPositions(owner: String) async throws -> [Position] {
        var components = URLComponents(string: "https://api2.hawksight.co/v1/positions/open")!
        components.queryItems = [URLQueryItem(name: "wallet", value: owner)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try validate(response)
        let open = try JSONDecoder().decode(HawksightOpenResponse.self, from: data)

        var result: [Position] = []
        for (poolAddress, positions) in open.pools {
            let pool = try? await fetchPool(address: poolAddress)
            for position in positions {
                let analytics = try? await fetchAnalytics(positionAddress: position.positionAddress)
                result.append(position.toPosition(poolAddress: poolAddress, pool: pool, analytics: analytics))
            }
        }
        return result
    }

    private func fetchPool(address: String) async throws -> HawksightPool? {
        var components = URLComponents(string: "https://pool.hawksight.co/v2/pools/meteora")!
        components.queryItems = [URLQueryItem(name: "keyword", value: address)]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try validate(response)
        return try JSONDecoder().decode(HawksightPoolResponse.self, from: data).pools
            .first { $0.address == address }
    }

    private func fetchAnalytics(positionAddress: String) async throws -> HawksightAnalytics {
        let url = URL(string: "https://api2.hawksight.co/v2/analytics/\(positionAddress)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response)
        let envelopes = try JSONDecoder().decode([HawksightAnalyticsEnvelope].self, from: data)
        let periodic = envelopes
            .flatMap(\.periodic)
            .filter { $0.position == positionAddress }
            .max { $0.datehour < $1.datehour }
        let metrics = envelopes.compactMap(\.aggMetrics).first { $0.position == positionAddress }
            ?? envelopes.compactMap(\.aggMetrics).first
        return HawksightAnalytics(periodic: periodic, metrics: metrics)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HawksightError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
    }
}

private struct HawksightOpenResponse: Decodable {
    let pools: [String: [HawksightOpenPosition]]
}

private struct HawksightOpenPosition: Decodable {
    let positionAddress: String
    let balances: [HawksightAmount]
    let fees: [HawksightAmount]
    let info: HawksightPositionInfo

    func toPosition(poolAddress: String, pool: HawksightPool?, analytics: HawksightAnalytics?) -> Position {
        let mintX = pool?.mintX ?? balances.first?.mint ?? ""
        let mintY = pool?.mintY ?? balances.dropFirst().first?.mint ?? ""
        let amountX = amount(in: balances, mint: mintX)
        let amountY = amount(in: balances, mint: mintY)
        let feeX = amount(in: fees, mint: mintX)
        let feeY = amount(in: fees, mint: mintY)
        let priceX = analytics?.periodic?.xPriceUsd ?? 0
        let priceY = analytics?.periodic?.yPriceUsd ?? 0
        let currentValue = amountX * priceX + amountY * priceY
        let uncollected = feeX * priceX + feeY * priceY
        let claimed = analytics?.metrics?.totalClaimedFeesUsd ?? 0
        let deposits = analytics?.metrics?.totalDeposits ?? 0
        let withdrawals = analytics?.metrics?.totalWithdrawals ?? 0
        let invested = max(deposits - withdrawals, 0)
        let pnlValue = currentValue + uncollected + claimed + withdrawals - deposits
        let pnlPercent = invested > 0 ? pnlValue / invested * 100 : 0
        let solPrice = mintY == "So11111111111111111111111111111111111111112" ? priceY : 0
        let activeBin = inferredActiveBin
        let inRange = activeBin >= info.lowerBinId && activeBin <= info.upperBinId
        let lowerPrice = analytics?.periodic?.lowerPrice ?? binPrice(info.lowerBinId)
        let upperPrice = analytics?.periodic?.upperPrice ?? binPrice(info.upperBinId)
        let currentPrice = analytics?.periodic?.pairPrice ?? binPrice(activeBin)
        let symbolX = pool?.tokenXSymbol ?? shortMint(mintX)
        let symbolY = pool?.tokenYSymbol ?? shortMint(mintY)

        return Position(
            id: positionAddress,
            pairName: "\(symbolX)/\(symbolY)",
            tokenName0: symbolX,
            tokenName1: symbolY,
            value: currentValue,
            inRange: inRange,
            strategyType: "Hawksight",
            priceRange: [lowerPrice, upperPrice, currentPrice],
            range: [info.lowerBinId, info.upperBinId, activeBin],
            tickLower: info.lowerBinId,
            tickUpper: info.upperBinId,
            pool: poolAddress,
            unCollectedFee: uncollected,
            amount0: amountX,
            amount1: amountY,
            feeAmount0: feeX,
            feeAmount1: feeY,
            logo0: pool?.tokenXIcon,
            logo1: pool?.tokenYIcon,
            bins: info.positionBinData.map {
                BinInfo(
                    binId: $0.binId,
                    binXAmount: $0.binXAmount,
                    binYAmount: $0.binYAmount,
                    positionXAmount: $0.positionXAmount,
                    positionYAmount: $0.positionYAmount,
                    positionLiquidity: $0.positionLiquidity
                )
            },
            pnl: PnL(
                value: pnlValue,
                percent: pnlPercent,
                valueNative: solPrice > 0 ? pnlValue / solPrice : nil,
                percentNative: solPrice > 0 ? pnlPercent : nil
            ),
            valueNative: solPrice > 0 ? currentValue / solPrice : 0,
            investedValue: analytics?.metrics == nil ? nil : invested,
            claimedFee: analytics?.metrics == nil ? nil : claimed,
            externalURL: "https://www.hawkfi.ag/meteora/\(poolAddress)"
        )
    }

    private func amount(in amounts: [HawksightAmount], mint: String) -> Double {
        Double(amounts.first { $0.mint == mint }?.amount ?? "0") ?? 0
    }

    private var inferredActiveBin: Int {
        if let mixed = info.positionBinData.first(where: {
            (Double($0.positionXAmount ?? "0") ?? 0) > 0 &&
            (Double($0.positionYAmount ?? "0") ?? 0) > 0
        }) { return mixed.binId }

        let firstX = info.positionBinData.first {
            (Double($0.positionXAmount ?? "0") ?? 0) > 0
        }?.binId
        let lastY = info.positionBinData.last {
            (Double($0.positionYAmount ?? "0") ?? 0) > 0
        }?.binId
        return firstX ?? lastY ?? ((info.lowerBinId + info.upperBinId) / 2)
    }

    private func binPrice(_ binId: Int) -> Double {
        guard let value = info.positionBinData.first(where: { $0.binId == binId })?.pricePerToken else { return 0 }
        return Double(value) ?? 0
    }

    private func shortMint(_ mint: String) -> String {
        guard mint.count > 8 else { return mint }
        return "\(mint.prefix(4))…\(mint.suffix(4))"
    }
}

private struct HawksightAmount: Decodable {
    let amount: String
    let mint: String
}

private struct HawksightPositionInfo: Decodable {
    let lowerBinId: Int
    let upperBinId: Int
    let positionBinData: [HawksightBin]
}

private struct HawksightBin: Decodable {
    let binId: Int
    let pricePerToken: String?
    let binXAmount: String?
    let binYAmount: String?
    let positionXAmount: String?
    let positionYAmount: String?
    let positionLiquidity: String?
}

private struct HawksightPoolResponse: Decodable {
    let pools: [HawksightPool]
}

private struct HawksightPool: Decodable {
    let address: String
    let mintX: String
    let mintY: String
    let tokenXSymbol: String
    let tokenYSymbol: String
    let tokenXIcon: String?
    let tokenYIcon: String?

    private enum CodingKeys: String, CodingKey {
        case address
        case mintX = "mint_x"
        case mintY = "mint_y"
        case tokenXSymbol = "token_x_symbol"
        case tokenYSymbol = "token_y_symbol"
        case tokenXIcon = "token_x_icon"
        case tokenYIcon = "token_y_icon"
    }
}

private struct HawksightAnalytics {
    let periodic: HawksightPeriodic?
    let metrics: HawksightMetrics?
}

private struct HawksightAnalyticsEnvelope: Decodable {
    let periodic: [HawksightPeriodic]
    let aggMetrics: HawksightMetrics?

    private enum CodingKeys: String, CodingKey {
        case periodic
        case aggMetrics = "agg_metrics"
    }
}

private struct HawksightPeriodic: Decodable {
    let datehour: String
    let position: String
    let xPriceUsd: Double?
    let yPriceUsd: Double?
    let pairPrice: Double?
    let upperPrice: Double?
    let lowerPrice: Double?

    private enum CodingKeys: String, CodingKey {
        case datehour, position
        case xPriceUsd = "x_price_usd"
        case yPriceUsd = "y_price_usd"
        case pairPrice = "pair_price"
        case upperPrice = "upper_price"
        case lowerPrice = "lower_price"
    }
}

private struct HawksightMetrics: Decodable {
    let position: String
    let totalClaimedFeesUsd: Double?
    let totalDeposits: Double?
    let totalWithdrawals: Double?

    private enum CodingKeys: String, CodingKey {
        case position
        case totalClaimedFeesUsd = "total_claimed_fees_usd"
        case totalDeposits = "total_deposits"
        case totalWithdrawals = "total_withdrawals"
    }
}

private enum HawksightError: LocalizedError {
    case badResponse(Int?)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "Hawksight request failed (HTTP \(status.map(String.init) ?? "unknown"))."
        }
    }
}
