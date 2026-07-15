import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(PositionStore.self) var store

    var body: some View {
        let totalPositions = store.wallets.reduce(0) {
            $0 + store.positions(for: $1).count + store.uniswapPositions(for: $1).count
        }
        let useWide = totalPositions > 3

        VStack(alignment: .leading, spacing: 12) {
            if store.wallets.isEmpty {
                ContentUnavailableView("No wallets", systemImage: "wallet.pass", description: Text("Add your API key and wallets from Settings."))
                    .frame(height: 120)
            } else {
                ForEach(store.wallets) { wallet in
                    if wallet.resolvedNetwork == .evm {
                        UniswapWalletSection(name: wallet.displayName,
                                             positions: store.uniswapPositions(for: wallet),
                                             twoColumn: useWide)
                    } else {
                        WalletSection(name: wallet.displayName,
                                      positions: store.positions(for: wallet),
                                      showBins: true,
                                      meteoraBase: wallet.linkMode.baseURL,
                                      twoColumn: useWide)
                    }
                }
            }
            BottomBar()
        }
        .padding(16)
        .frame(width: useWide ? 860 : 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Wallet Section

struct WalletSection: View {
    let name: String
    let positions: [Position]
    let showBins: Bool
    let meteoraBase: String
    let twoColumn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(2)
                .padding(.leading, 2)

            if positions.isEmpty {
                Text("No open positions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else if twoColumn {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(positions) { pos in
                        PositionCard(position: pos, showBins: showBins, meteoraBase: meteoraBase)
                    }
                }
            } else {
                ForEach(positions) { pos in
                    PositionCard(position: pos, showBins: showBins, meteoraBase: meteoraBase)
                }
            }
        }
    }
}

struct UniswapWalletSection: View {
    let name: String
    let positions: [UniswapPosition]
    let twoColumn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(2)
                .padding(.leading, 2)

            if positions.isEmpty {
                Text("No open positions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else if twoColumn {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(positions) { UniswapPositionCard(position: $0) }
                }
            } else {
                ForEach(positions) { UniswapPositionCard(position: $0) }
            }
        }
    }
}

struct UniswapPositionCard: View {
    let position: UniswapPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(position.inRange ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Button {
                    if let url = position.appURL { NSWorkspace.shared.open(url) }
                } label: {
                    Text(position.pairName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .underline(color: .primary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(position.appURL == nil)
                Spacer()
                Text(formatUSD(position.valueUsd))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }

            Divider().opacity(0.3)

            HStack(spacing: 0) {
                Label_("Pos")
                Text("\(formatToken(position.amount0)) \(position.token0.symbol)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("  +  ").foregroundStyle(.tertiary)
                Text("\(formatToken(position.amount1)) \(position.token1.symbol)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                Label_("Fee")
                Text(formatUSD(position.uncollectedFeesUsd))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.yellow)
                Spacer()
                if let apr = position.apr {
                    Text("APR \(String(format: "%.2f%%", apr))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                Label_("Ticks")
                Text("\(position.tickLower)  –  \(position.tickUpper)   ▸  \(position.currentTick)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.3)
            UniswapMarketCapRangeView(position: position)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        )
    }
}

struct UniswapMarketCapRangeView: View {
    let position: UniswapPosition

    private var markerColor: Color { position.inRange ? .green : .red }

    var body: some View {
        VStack(spacing: 6) {
            if let range = position.marketCapRange {
                HStack {
                    Text(formatCompactUSD(range.lower))
                    Spacer()
                    Text("MCAP \(formatCompactUSD(range.current))")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formatCompactUSD(range.upper))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let raw = position.marketCapRangePercent
                let markerX = min(max(raw, 0), 1) * proxy.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 8)
                    Capsule()
                        .fill(Color.green.opacity(position.inRange ? 0.55 : 0.25))
                        .frame(height: 8)
                    Rectangle()
                        .fill(markerColor)
                        .frame(width: 2, height: 18)
                        .offset(x: markerX - 1)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)

            HStack {
                Text("LOWER")
                Spacer()
                Text(position.inRange ? "IN RANGE" : "OUT OF RANGE")
                    .foregroundStyle(markerColor)
                Spacer()
                Text("UPPER")
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
    }
}

enum RangeStatus {
    case inRange, out
    var color: Color {
        switch self {
        case .inRange: return .green
        case .out:     return Color(red: 1, green: 0.3, blue: 0.3)
        }
    }
}

// MARK: - Position Card

struct PositionCard: View {
    let position: Position
    let showBins: Bool
    let meteoraBase: String

    var pnlColor: Color { position.pnl.value >= 0 ? .green : Color(red: 1, green: 0.35, blue: 0.35) }
    var title: String { position.pairName.contains("/") ? position.pairName : "\(position.pairName)/\(position.tokenName1)" }

    /// Client-side range check — overrides API's inRange when activeBin drifts outside bounds
    var rangeStatus: RangeStatus {
        let pct = position.activeBinPercent
        if !position.inRange || pct < 0 || pct > 1 { return .out }
        return .inRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(rangeStatus.color)
                    .frame(width: 7, height: 7)

                Button {
                    if let url = URL(string: "\(meteoraBase)/\(position.pool)?referrer=portfolio") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .underline(color: .primary.opacity(0.3))
                }
                .buttonStyle(.plain)

                Spacer()

                if position.valueNative > 0 {
                    Text("\(formatSOL(position.valueNative)) SOL")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(formatUSD(position.value))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 10)

            Divider().opacity(0.3)
                .padding(.bottom, 10)

            // ── Stats grid ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {

                // Range
                if position.priceRange.count >= 3 {
                    HStack(spacing: 0) {
                        Label_("Range")
                        Text("\(formatPrice(position.priceRange[0]))  –  \(formatPrice(position.priceRange[1]))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.75))
                        Text("   ▸  \(formatPrice(position.priceRange[2]))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.orange)
                    }
                }

                // Position token amounts
                if position.amount0 > 0 || position.amount1 > 0 {
                    HStack(spacing: 0) {
                        Label_("Pos")
                        Text("\(formatToken(position.amount0)) \(position.tokenName0)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("  +  ")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text("\(formatToken(position.amount1)) \(position.tokenName1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // Fee + Strategy
                HStack(spacing: 0) {
                    Label_("Fee")
                    Text(formatUSD(position.unCollectedFee))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3))
                    Spacer()
                    Text(position.strategyType)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Fee token breakdown
                if position.feeAmount0 > 0 || position.feeAmount1 > 0 {
                    HStack(spacing: 0) {
                        Label_("")
                        Text("\(formatToken(position.feeAmount0)) \(position.tokenName0)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3).opacity(0.75))
                        Text("  +  ")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text("\(formatToken(position.feeAmount1)) \(position.tokenName1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3).opacity(0.75))
                    }
                }

                // PnL
                HStack(spacing: 0) {
                    Label_("PnL")
                    Text("\(position.pnl.value >= 0 ? "+" : "")\(formatUSD(position.pnl.value))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(pnlColor)
                    Text("  \(position.pnl.percent >= 0 ? "+" : "")\(String(format: "%.2f%%", position.pnl.percent))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(pnlColor.opacity(0.8))
                }

                // PnL in SOL
                if let solVal = position.pnl.valueNative, let solPct = position.pnl.percentNative {
                    let solPnlColor: Color = solVal >= 0 ? .green : Color(red: 1, green: 0.35, blue: 0.35)
                    HStack(spacing: 0) {
                        Label_("")
                        Text("\(solVal >= 0 ? "+" : "")\(formatSOL(solVal)) SOL")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(solPnlColor.opacity(0.85))
                        Text("  \(solPct >= 0 ? "+" : "")\(String(format: "%.2f%%", solPct))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(solPnlColor.opacity(0.65))
                    }
                }
            }

            // ── Bins bar ────────────────────────────────────────
            if showBins {
                Divider().opacity(0.3).padding(.vertical, 10)
                StrategyBinsView(position: position)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Small label helper

private struct Label_: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text("\(text)  ")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 46, alignment: .leading)
    }
}

// MARK: - Strategy Bins View

struct StrategyBinsView: View {
    let position: Position

    private let solColor   = Color(red: 0.25, green: 0.78, blue: 1.0)
    private let tokenColor = Color(red: 0.58, green: 0.42, blue: 1.0)

    // Actual number of bins in the position's range
    private var binCount: Int {
        let count = position.tickUpper - position.tickLower
        return max(count, 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Token labels
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(solColor).frame(width: 6, height: 6)
                    Text(position.tokenName1)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(solColor)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(position.pairName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokenColor)
                    Circle().fill(tokenColor).frame(width: 6, height: 6)
                }
            }

            // Bar chart
            Canvas { ctx, size in
                let n         = binCount
                let heights   = computeHeights()
                let pct       = position.activeBinPercent
                let activeIdx = Int((pct * Double(n - 1)).rounded())
                let barW      = size.width / CGFloat(n)
                // Gap: 1px when many bars, slightly more for few bars
                let gap       = CGFloat(n > 40 ? 1.0 : 1.5)

                for i in 0..<n {
                    let h    = CGFloat(heights[i])
                    let barH = size.height * h
                    let x    = CGFloat(i) * barW + gap / 2
                    let rect = CGRect(x: x, y: size.height - barH,
                                      width: max(barW - gap, 1), height: barH)

                    // Color: left of active = SOL, right = token
                    let base: Color = i <= activeIdx ? solColor : tokenColor
                    // Slight fade near active bin for depth
                    let distFromActive = abs(Double(i) - Double(activeIdx)) / Double(n)
                    let alpha = 0.55 + distFromActive * 0.45
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.0),
                             with: .color(base.opacity(alpha)))
                }

                // Dashed active-bin line
                let ax = CGFloat(pct) * size.width
                var line = Path()
                line.move(to: CGPoint(x: ax, y: 0))
                line.addLine(to: CGPoint(x: ax, y: size.height))
                ctx.stroke(line,
                           with: .color(.white.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            }
            .frame(height: 52)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))

            // Tick labels
            HStack {
                Text("bin \(position.tickLower)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("active \(position.activeBin)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("bin \(position.tickUpper)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // ── Height distribution per strategy ─────────────────────────
    private func computeHeights() -> [Double] {
        let n         = binCount
        let pct       = max(0.001, min(0.999, position.activeBinPercent))
        let activeIdx = Int((pct * Double(n - 1)).rounded())
        let strat     = position.strategyType.lowercased()

        var h = [Double](repeating: 0, count: n)

        if strat.contains("curve") {
            // Bell curve: peak at active bin, tapering toward edges
            let sigma = Double(n) * 0.22
            for i in 0..<n {
                let dx = Double(i) - Double(activeIdx)
                h[i] = exp(-0.5 * (dx / sigma) * (dx / sigma))
            }

        } else if strat.contains("bidask") {
            // Single continuous descent left→right across ALL bins.
            // Active bin line just splits the color (SOL vs token).
            // Punch: active near right → long cyan ramp, tiny purple end
            // Clude: active near middle → cyan ramp then shorter purple ramp
            for i in 0..<n {
                // 1.0 (far left) → 0.1 (far right): "10m bina ... 1m bina"
                h[i] = 1.0 - (Double(i) / Double(n - 1)) * 0.9
            }

        } else {
            // Spot: flat rectangle — all bars equal height
            for i in 0..<n { h[i] = 1.0 }
        }

        let maxH = h.max() ?? 1.0
        let floor: Double = strat.contains("spot") ? 1.0 : 0.0
        return h.map { max(floor, $0 / maxH) }
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    @Environment(PositionStore.self) var store

    var body: some View {
        HStack(spacing: 8) {
            if store.isLoading {
                ProgressView().scaleEffect(0.55)
                Text("Refreshing…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let updated = store.lastUpdated {
                Text("Updated \(timeString(updated))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                SettingsWindow.shared.open(store: store)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.isLoading)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - Settings

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSPanel?

    @MainActor
    func open(store: PositionStore) {
        hideMenuBarWindow()

        if let window {
            bringToFront(window)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "viemora Settings"
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SettingsView(onClose: { [weak self, weak panel] in
            panel?.close()
            self?.window = nil
        }).environment(store))

        window = panel
        bringToFront(panel)
    }

    @MainActor
    private func hideMenuBarWindow() {
        for candidate in NSApp.windows {
            if let window, candidate === window { continue }
            candidate.orderOut(nil)
        }
    }

    @MainActor
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              let current = window,
              closing === current else { return }
        window = nil
    }
}

struct SettingsView: View {
    @Environment(PositionStore.self) var store
    var onClose: () -> Void = {}
    @State private var draftWallets: [WalletConfig] = []
    @State private var apiKey = ""
    @State private var settingsError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button {
                    draftWallets.append(WalletConfig(name: "", address: "", linkMode: .app))
                } label: {
                    Label("Add Wallet", systemImage: "plus")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LPAgent API")
                    .font(.headline)
                SecureField("LPAgent API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Wallets")
                    .font(.headline)

                if draftWallets.isEmpty {
                    Text("No wallets yet. Add one to start tracking positions.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach($draftWallets) { $wallet in
                                WalletSettingsRow(wallet: $wallet) {
                                    draftWallets.removeAll { $0.id == wallet.id }
                                }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 160)
                }
            }

            if let settingsError {
                Text(settingsError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            HStack {
                Text("Link seçimi pozisyon başlığına tıklayınca hangi Meteora domaininin açılacağını belirler.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onClose() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 680, height: 430)
        .onAppear {
            draftWallets = store.wallets
            apiKey = APIKeyStore.apiKey ?? ""
        }
    }

    private func save() {
        do {
            try APIKeyStore.saveAPIKey(apiKey)
            store.saveWallets(draftWallets)
            onClose()
        } catch {
            settingsError = error.localizedDescription
        }
    }
}

struct WalletSettingsRow: View {
    @Binding var wallet: WalletConfig
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $wallet.name)
                .frame(width: 90)
            TextField("Wallet address", text: $wallet.address)
                .textFieldStyle(.roundedBorder)
            Picker("Network", selection: Binding(
                get: { wallet.resolvedNetwork },
                set: { wallet.network = $0 }
            )) {
                ForEach(WalletNetwork.allCases) { network in
                    Text(network.title).tag(network)
                }
            }
            .labelsHidden()
            .frame(width: 85)
            if wallet.resolvedNetwork == .solana {
                Picker("Link", selection: $wallet.linkMode) {
                    ForEach(MeteoraLinkMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Formatters

private func formatUSD(_ value: Double) -> String {
    if abs(value) >= 10000 { return String(format: "$%.0f", value) }
    if abs(value) >= 100   { return String(format: "$%.2f", value) }
    if abs(value) >= 1     { return String(format: "$%.2f", value) }
    return String(format: "$%.4f", value)
}

private func formatCompactUSD(_ value: Double) -> String {
    let magnitude = abs(value)
    if magnitude >= 1_000_000_000 { return String(format: "$%.2fB", value / 1_000_000_000) }
    if magnitude >= 1_000_000 { return String(format: "$%.2fM", value / 1_000_000) }
    if magnitude >= 1_000 { return String(format: "$%.1fK", value / 1_000) }
    return formatUSD(value)
}

private func formatSOL(_ value: Double) -> String {
    if abs(value) >= 1000 { return String(format: "%.1f", value) }
    if abs(value) >= 1    { return String(format: "%.3f", value) }
    if abs(value) >= 0.01 { return String(format: "%.4f", value) }
    return String(format: "%.6f", value)
}

private func formatToken(_ amount: Double) -> String {
    if amount >= 1_000_000 { return String(format: "%.2fM", amount / 1_000_000) }
    if amount >= 1_000     { return String(format: "%.1fK", amount / 1_000) }
    if amount >= 1         { return String(format: "%.3f", amount) }
    if amount >= 0.0001    { return String(format: "%.6f", amount) }
    return String(format: "%.8f", amount)
}

private func formatPrice(_ p: Double) -> String {
    if p >= 100  { return String(format: "%.0f", p) }
    if p >= 1    { return String(format: "%.2f", p) }
    if p >= 0.01 { return String(format: "%.4f", p) }
    return String(format: "%.6f", p)
}

#Preview {
    ContentView()
        .environment(PositionStore())
}
