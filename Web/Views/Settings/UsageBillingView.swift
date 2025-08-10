import SwiftUI

struct UsageBillingView: View {
    @ObservedObject private var usageStore = AIUsageStore.shared
    @ObservedObject private var budgetManager = UsageBudgetManager.shared

    @State private var range: RangeOption = .last7Days
    @State private var showCSV = false

    enum RangeOption: String, CaseIterable, Identifiable {
        case today = "Today"
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"
        var id: String { rawValue }

        func bounds(now: Date = Date()) -> ClosedRange<Date> {
            let cal = Calendar.current
            switch self {
            case .today:
                let start = cal.startOfDay(for: now)
                return start...now
            case .last7Days:
                let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
                return start...now
            case .last30Days:
                let start =
                    cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? now
                return start...now
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Usage & Billing")
                .font(.title3).fontWeight(.semibold)

            HStack(spacing: 12) {
                Picker("Range", selection: $range) {
                    ForEach(RangeOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button("Export CSV") { showCSV.toggle() }
            }

            usageSparkline

            usageTotalsSection

            budgetsSection
        }
        .sheet(isPresented: $showCSV) {
            let csv = AIUsageStore.shared.exportCSV(in: range.bounds())
            ScrollView {
                Text(csv).textSelection(.enabled).font(.system(.caption, design: .monospaced))
                    .padding()
            }
            .frame(width: 700, height: 500)
        }
    }

    // MARK: - Simple Sparkline for Total Tokens (by day)
    private var usageSparkline: some View {
        let bounds = range.bounds()
        let events = usageStore.events(in: bounds)
        let cal = Calendar.current
        let days = stride(
            from: 0,
            through: cal.dateComponents(
                [.day], from: cal.startOfDay(for: bounds.lowerBound),
                to: cal.startOfDay(for: bounds.upperBound)
            ).day ?? 0, by: 1
        )
        .compactMap { offset -> (Date, Int) in
            let day = cal.date(
                byAdding: .day, value: offset, to: cal.startOfDay(for: bounds.lowerBound))!
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day)!
            let total = events.filter { $0.timestamp >= day && $0.timestamp < dayEnd }.reduce(0) {
                $0 + $1.totalTokens
            }
            return (day, total)
        }
        let maxValue = max(1, days.map { $0.1 }.max() ?? 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Trend")
                .font(.headline)
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(days.enumerated()), id: \.offset) { pair in
                        let item = pair.element
                        let height = CGFloat(item.1) / CGFloat(maxValue) * max(12, geo.size.height)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: 6, height: max(2, height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 60)
        }
    }

    private var usageTotalsSection: some View {
        let bounds = range.bounds()
        let totals = usageStore.aggregate(in: bounds)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Totals by Provider/Model")
                .font(.headline)
            if totals.isEmpty {
                Text("No usage in selected range.").foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(totals, id: \.providerId) { t in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(t.providerId) • \(t.modelId)")
                                    .fontWeight(.medium)
                                Text(
                                    "Tokens: \(t.totalTokens)  •  Cost: $\(String(format: "%.4f", t.estimatedCostUSD))"
                                )
                                .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(t.requestCount) reqs").font(.caption)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(
                                Color(NSColor.controlBackgroundColor)))
                    }
                }
            }
        }
    }

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budgets")
                .font(.headline)

            let providers = AIProviderManager.shared.availableProviders
            ForEach(providers, id: \.providerId) { p in
                let current =
                    budgetManager.getBudget(for: p.providerId)
                    ?? UsageBudgetManager.Budget(
                        dailyUSD: nil, monthlyUSD: nil, blockOnExceed: false)
                BudgetRow(providerId: p.providerId, initial: current)
            }
        }
    }
}

private struct BudgetRow: View {
    let providerId: String
    @State var daily: String
    @State var monthly: String
    @State var blockOnExceed: Bool

    init(providerId: String, initial: UsageBudgetManager.Budget) {
        self.providerId = providerId
        self._daily = State(initialValue: initial.dailyUSD.map { String($0) } ?? "")
        self._monthly = State(initialValue: initial.monthlyUSD.map { String($0) } ?? "")
        self._blockOnExceed = State(initialValue: initial.blockOnExceed)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(providerId).frame(width: 120, alignment: .leading)
            TextField("Daily $", text: $daily)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            TextField("Monthly $", text: $monthly)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            Toggle("Block on exceed", isOn: $blockOnExceed)
            Spacer()
            Button("Save") {
                UsageBudgetManager.shared.setBudget(
                    for: providerId,
                    budget: .init(
                        dailyUSD: Double(daily),
                        monthlyUSD: Double(monthly),
                        blockOnExceed: blockOnExceed
                    )
                )
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1)))
    }
}

#Preview {
    UsageBillingView().frame(width: 700, height: 600)
}
