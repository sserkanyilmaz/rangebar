import Foundation
import Observation

class LPAgentService {
    static let shared = LPAgentService()

    private let baseURL = "https://api.lpagent.io/open-api/v1"

    func fetchOpenPositions(owner: String) async throws -> [Position] {
        guard let apiKey = APIKeyStore.apiKey else {
            throw LPAgentError.missingAPIKey
        }

        var components = URLComponents(string: "\(baseURL)/lp-positions/opening")!
        components.queryItems = [URLQueryItem(name: "owner", value: owner)]

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(PositionDTOResponse.self, from: data)
        return response.data.map { $0.toPosition() }
    }
}

enum LPAgentError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set LPAgent API key in Settings."
        }
    }
}

@Observable
@MainActor
class PositionStore {
    var wallets: [WalletConfig] = []
    var positionsByWallet: [UUID: [Position]] = [:]
    var uniswapPositionsByWallet: [UUID: [UniswapPosition]] = [:]
    var isLoading = false
    var lastUpdated: Date?
    var errorMessage: String?

    private var refreshTask: Task<Void, Never>?
    private let walletsKey = "walletConfigs"

    init() {
        loadWallets()
        Task { await refresh() }
        startAutoRefresh()
    }

    func positions(for wallet: WalletConfig) -> [Position] {
        positionsByWallet[wallet.id] ?? []
    }

    func uniswapPositions(for wallet: WalletConfig) -> [UniswapPosition] {
        uniswapPositionsByWallet[wallet.id] ?? []
    }

    func saveWallets(_ newWallets: [WalletConfig]) {
        wallets = newWallets
            .map { wallet in
                var cleaned = wallet
                cleaned.name = wallet.name.trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned.address = wallet.address.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned
            }
            .filter { !$0.address.isEmpty }

        if let data = try? JSONEncoder().encode(wallets) {
            UserDefaults.standard.set(data, forKey: walletsKey)
        }

        let validIDs = Set(wallets.map(\.id))
        positionsByWallet = positionsByWallet.filter { validIDs.contains($0.key) }
        uniswapPositionsByWallet = uniswapPositionsByWallet.filter { validIDs.contains($0.key) }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            var nextSolana: [UUID: [Position]] = [:]
            var nextEVM: [UUID: [UniswapPosition]] = [:]
            for wallet in wallets where !wallet.address.isEmpty {
                switch wallet.resolvedNetwork {
                case .solana:
                    nextSolana[wallet.id] = try await LPAgentService.shared.fetchOpenPositions(owner: wallet.address)
                case .evm:
                    nextEVM[wallet.id] = try await UniswapService.shared.fetchPositions(owner: wallet.address)
                }
            }
            positionsByWallet = nextSolana
            uniswapPositionsByWallet = nextEVM
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadWallets() {
        if let data = UserDefaults.standard.data(forKey: walletsKey),
           let saved = try? JSONDecoder().decode([WalletConfig].self, from: data) {
            wallets = saved
        } else {
            wallets = []
        }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await refresh()
            }
        }
    }
}
