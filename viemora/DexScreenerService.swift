import Foundation

@MainActor
final class DexScreenerService {
    static let shared = DexScreenerService()

    private struct CacheEntry {
        let value: UniswapMarketData?
        let date: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private var tokenCache: [String: CacheEntry] = [:]
    private let cacheLifetime: TimeInterval = 55

    func marketData(chainId: Int, poolId: String) async throws -> UniswapMarketData? {
        guard let chain = UniswapChain.dexScreenerSlug(for: chainId) else { return nil }
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
        guard let poolPair = decoded.pair ?? decoded.pairs?.first else {
            cache[key] = CacheEntry(value: nil, date: Date())
            return nil
        }

        // A position's pool can be thin and trade away from the token's main market.
        // Use the most liquid pair for the current token market cap, while the
        // Uniswap pool ticks remain the source for the position's range.
        let value = try await canonicalMarketData(
            chain: chain,
            tokenAddress: poolPair.baseToken.address,
            fallback: poolPair
        )
        cache[key] = CacheEntry(value: value, date: Date())
        return value
    }
    private func canonicalMarketData(
        chain: String,
        tokenAddress: String,
        fallback: DexScreenerPair
    ) async throws -> UniswapMarketData? {
        let tokenKey = "\(chain):\(tokenAddress.lowercased())"
        if let cached = tokenCache[tokenKey], Date().timeIntervalSince(cached.date) < cacheLifetime {
            return cached.value
        }

        let pairs: [DexScreenerPair]
        if let url = URL(string: "https://api.dexscreener.com/token-pairs/v1/\(chain)/\(tokenAddress)") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                pairs = (try? JSONDecoder().decode([DexScreenerPair].self, from: data)) ?? []
            } else {
                pairs = []
            }
        } else {
            pairs = []
        }

        let address = tokenAddress.lowercased()
        let canonical = pairs
            .filter {
                $0.baseToken.address.lowercased() == address &&
                (($0.marketCap ?? $0.fdv) ?? 0) > 0
            }
            .max { ($0.liquidity?.usd ?? 0) < ($1.liquidity?.usd ?? 0) }
        let selected = canonical ?? fallback
        let cap = selected.marketCap ?? selected.fdv

        let value: UniswapMarketData?
        if let cap, cap > 0 {
            value = UniswapMarketData(
                baseTokenAddress: tokenAddress,
                marketCap: cap,
                priceUsd: selected.priceUsd.flatMap(Double.init),
                liquidityUsd: selected.liquidity?.usd
            )
        } else {
            value = nil
        }

        tokenCache[tokenKey] = CacheEntry(value: value, date: Date())
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
