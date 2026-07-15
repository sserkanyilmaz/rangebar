import Foundation

@MainActor
final class DexScreenerService {
    static let shared = DexScreenerService()

    private struct CacheEntry {
        let value: UniswapMarketData?
        let date: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheLifetime: TimeInterval = 55

    func marketData(chainId: Int, poolId: String) async throws -> UniswapMarketData? {
        guard let chain = UniswapChain.slug(for: chainId) else { return nil }
        let key = "\(chain):\(poolId.lowercased())"

        if let cached = cache[key], Date().timeIntervalSince(cached.date) < cacheLifetime {
            return cached.value
        }

        guard let url = URL(string: "https://api.dexscreener.com/latest/dex/pairs/\(chain)/\(poolId)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DexScreenerError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }

        let decoded = try JSONDecoder().decode(DexScreenerResponse.self, from: data)
        let pair = decoded.pair ?? decoded.pairs?.first
        let cap = pair?.marketCap ?? pair?.fdv
        let value: UniswapMarketData?
        if let pair, let cap, cap > 0 {
            value = UniswapMarketData(
                baseTokenAddress: pair.baseToken.address,
                marketCap: cap,
                priceUsd: pair.priceUsd.flatMap(Double.init),
                liquidityUsd: pair.liquidity?.usd
            )
        } else {
            value = nil
        }

        cache[key] = CacheEntry(value: value, date: Date())
        return value
    }
}

private struct DexScreenerResponse: Decodable {
    let pair: DexScreenerPair?
    let pairs: [DexScreenerPair]?
}

private struct DexScreenerPair: Decodable {
    let baseToken: DexScreenerToken
    let priceUsd: String?
    let marketCap: Double?
    let fdv: Double?
    let liquidity: DexScreenerLiquidity?
}

private struct DexScreenerToken: Decodable {
    let address: String
}

private struct DexScreenerLiquidity: Decodable {
    let usd: Double?
}

private enum DexScreenerError: LocalizedError {
    case badResponse(Int?)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "DexScreener request failed (HTTP \(status.map(String.init) ?? "unknown"))."
        }
    }
}
