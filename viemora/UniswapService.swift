import Foundation

final class UniswapService {
    static let shared = UniswapService()

    private let endpoint = URL(string: "https://interface.gateway.uniswap.org/v2/data.v1.DataApiService/ListPositions")!
    private let chainIds = [1, 130, 8453, 42161, 4663, 4217, 143, 137, 196, 10, 56, 43114, 59144, 480, 324, 4326, 1868, 7777777, 42220, 81457]

    func fetchPositions(owner: String) async throws -> [UniswapPosition] {
        var result: [UniswapPosition] = []
        var pageToken: String?
        var visitedTokens = Set<String>()

        repeat {
            let page = try await fetchPage(owner: owner, pageToken: pageToken)
            result.append(contentsOf: page.positions.compactMap { $0.toPosition() })

            guard let next = page.nextPageToken, !next.isEmpty, visitedTokens.insert(next).inserted else {
                pageToken = nil
                break
            }
            pageToken = next
        } while visitedTokens.count < 20

        return Array(Dictionary(grouping: result, by: \.id).compactMap { $0.value.first })
    }

    private func fetchPage(owner: String, pageToken: String?) async throws -> UniswapPositionsResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("uniswap-web", forHTTPHeaderField: "x-request-source")
        request.httpBody = try JSONEncoder().encode(UniswapPositionsRequest(
            address: owner,
            chainIds: chainIds,
            protocolVersions: ["PROTOCOL_VERSION_V4", "PROTOCOL_VERSION_V3"],
            positionStatuses: ["POSITION_STATUS_IN_RANGE", "POSITION_STATUS_OUT_OF_RANGE"],
            pageSize: 25,
            includeHidden: true,
            pageToken: pageToken
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UniswapServiceError.badResponse((response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(UniswapPositionsResponse.self, from: data)
    }
}

private struct UniswapPositionsRequest: Encodable {
    let address: String
    let chainIds: [Int]
    let protocolVersions: [String]
    let positionStatuses: [String]
    let pageSize: Int
    let includeHidden: Bool
    let pageToken: String?
}

private struct UniswapPositionsResponse: Decodable {
    let positions: [UniswapPositionDTO]
    let nextPageToken: String?

    private enum CodingKeys: String, CodingKey {
        case positions, nextPageToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positions = try container.decodeIfPresent([UniswapPositionDTO].self, forKey: .positions) ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

private struct UniswapPositionDTO: Decodable {
    let chainId: Int
    let protocolVersion: String
    let v3Position: UniswapPoolPositionDTO?
    let v4Position: UniswapV4PositionDTO?
    let status: String
    let valueUsd: Double?
    let uncollectedFeesUsd: Double?

    func toPosition() -> UniswapPosition? {
        guard let position = v3Position ?? v4Position?.poolPosition else { return nil }
        return UniswapPosition(
            chainId: chainId,
            protocolVersion: protocolVersion,
            tokenId: position.tokenId,
            token0: position.token0,
            token1: position.token1,
            tickLower: Int(position.tickLower) ?? 0,
            tickUpper: Int(position.tickUpper) ?? 0,
            currentTick: Int(position.currentTick) ?? 0,
            amount0: adjusted(position.amount0, decimals: position.token0.decimals),
            amount1: adjusted(position.amount1, decimals: position.token1.decimals),
            feeAmount0: adjusted(position.token0UncollectedFees, decimals: position.token0.decimals),
            feeAmount1: adjusted(position.token1UncollectedFees, decimals: position.token1.decimals),
            valueUsd: valueUsd ?? 0,
            uncollectedFeesUsd: uncollectedFeesUsd ?? 0,
            apr: position.apr,
            status: status
        )
    }

    private func adjusted(_ raw: String, decimals: Int) -> Double {
        guard let value = Double(raw) else { return 0 }
        return value / pow(10, Double(decimals))
    }
}

private struct UniswapV4PositionDTO: Decodable {
    let poolPosition: UniswapPoolPositionDTO
}

private struct UniswapPoolPositionDTO: Decodable {
    let tokenId: String
    let tickLower: String
    let tickUpper: String
    let currentTick: String
    let token0: UniswapToken
    let token1: UniswapToken
    let token0UncollectedFees: String
    let token1UncollectedFees: String
    let amount0: String
    let amount1: String
    let apr: Double?
}

private enum UniswapServiceError: LocalizedError {
    case badResponse(Int?)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "Uniswap request failed (HTTP \(status.map(String.init) ?? "unknown"))."
        }
    }
}
