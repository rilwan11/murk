import SwiftUI
import StoreKit

enum Legal {
    static let privacy = URL(string: "https://github.com/rilwan11/murk/blob/main/PRIVACY.md")!
    static let terms = URL(string: "https://github.com/rilwan11/murk/blob/main/TERMS.md")!
    static let support = URL(string: "https://github.com/rilwan11/murk/issues")!
}

/// The Murk Pro offer. Shown only when someone reaches for a Pro feature, or opens it from Settings.
struct PaywallView: View {
    @EnvironmentObject var store: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    let reason: PaywallReason
    @State private var manage = false

    private var lead: String {
        switch reason {
        case .city: return String(localized: "Saving more than one city is part of Murk Pro.")
        case .skin: return String(localized: "This skin is part of Murk Pro.")
        case .alerts: return String(localized: "Rain, wind, UV and air-quality alerts are part of Murk Pro.")
        case .general: return String(localized: "Everything in Murk, plus more places, looks and alerts.")
        }
    }

    private let rows: [(String, String, String, Bool)] = [
        ("cloud.sun.fill", "Current conditions, 8-day forecast, all five pages", "", true),
        ("location.fill", "Current Location and one saved city", "", true),
        ("square.grid.2x2.fill", "Home and Lock Screen widgets", "", true),
        ("exclamationmark.triangle.fill", "Official weather alerts", "", true),
        ("mappin.and.ellipse", "Unlimited saved cities", "", false),
        ("paintpalette.fill", "Aurora, Storm and Sunset skins, plus Auto", "", false),
        ("bell.badge.fill", "Alerts for rain, wind, UV and air quality", "", false),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Murk Pro").font(.display(40))
                        Text(lead).font(.body).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("WHAT YOU GET").font(.mono(11)).tracking(1.5).foregroundStyle(.secondary)
                            Spacer()
                            Text("FREE").font(.mono(11)).frame(width: 44)
                            Text("PRO").font(.mono(11)).frame(width: 44)
                        }
                        .padding(.bottom, 8)
                        ForEach(rows.indices, id: \.self) { i in
                            let r = rows[i]
                            HStack(spacing: 10) {
                                Image(systemName: r.0).frame(width: 24).foregroundStyle(.secondary)
                                Text(LocalizedStringKey(r.1)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Image(systemName: r.3 ? "checkmark" : "minus").frame(width: 44)
                                    .foregroundStyle(r.3 ? Color.primary : Color.secondary)
                                    .accessibilityLabel(r.3 ? Text("Included in Free") : Text("Not in Free"))
                                Image(systemName: "checkmark").frame(width: 44).fontWeight(.bold)
                                    .accessibilityLabel(Text("Included in Pro"))
                            }
                            .padding(.vertical, 9)
                            .accessibilityElement(children: .combine)
                            if i < rows.count - 1 { Divider() }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))

                    if store.isPro {
                        Label("You have Murk Pro. Thank you.", systemImage: "checkmark.seal.fill").font(.headline)
                    } else if store.products.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.loadFailed ? "Murk Pro isn't available from the App Store right now." : "Loading prices…")
                                .foregroundStyle(.secondary)
                            if store.loadFailed {
                                Button("Try again") { Task { await store.loadProducts() } }.buttonStyle(.bordered)
                            }
                        }
                    } else {
                        ForEach(store.products, id: \.id) { p in planButton(p) }
                        Text("Payment is charged to your Apple ID. Subscriptions renew automatically at the price shown, each period, until you cancel. Cancel at least 24 hours before renewal in Settings › Apple ID › Subscriptions, or with Manage Subscription below.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    if let m = store.message {
                        Text(m).font(.footnote).foregroundStyle(.primary)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Button("Restore Purchases") { Task { await store.restore() } }
                        Button("Manage Subscription") { manage = true }
                        Link("Privacy Policy", destination: Legal.privacy)
                        Link("Terms of Use", destination: Legal.terms)
                    }
                    .font(.subheadline)
                    .disabled(store.isWorking)
                }
                .padding(20)
            }
            .background(Color(hex: 0x0B0B0B).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                        .accessibilityLabel("Close")
                }
            }
            .overlay { if store.isWorking { ProgressView().controlSize(.large) } }
        }
        .preferredColorScheme(.dark)
        .manageSubscriptionsSheet(isPresented: $manage)
        .task { if store.products.isEmpty { await store.loadProducts() } }
        .onChange(of: store.isPro) { _, pro in if pro && reason != .general { dismiss() } }
    }

    @ViewBuilder
    private func planButton(_ p: Product) -> some View {
        let period = p.subscription.map { Self.periodName($0.subscriptionPeriod) } ?? ""
        let trial: Product.SubscriptionOffer? = {
            guard store.trialEligible, let o = p.subscription?.introductoryOffer, o.paymentMode == .freeTrial else { return nil }
            return o
        }()
        Button {
            Task { await store.purchase(p) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let trial {
                    Text("Start \(Self.length(trial.period)) free trial").font(.headline)
                    Text("Free for \(Self.length(trial.period)), then \(p.displayPrice) per \(period). Renews automatically until canceled.")
                        .font(.footnote).multilineTextAlignment(.leading)
                } else {
                    Text("Subscribe for \(p.displayPrice) per \(period)").font(.headline)
                    Text("\(p.displayName) · renews automatically every \(period) until canceled.")
                        .font(.footnote).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xF2B33D)))
            .foregroundStyle(Color(hex: 0x1A1206))
        }
        .buttonStyle(.plain)
        .disabled(store.isWorking)
    }

    static func periodName(_ p: Product.SubscriptionPeriod) -> String {
        switch p.unit {
        case .day: return p.value == 7 ? String(localized: "week") : String(localized: "day")
        case .week: return String(localized: "week")
        case .month: return p.value == 1 ? String(localized: "month") : String(localized: "\(p.value) months")
        case .year: return String(localized: "year")
        @unknown default: return ""
        }
    }

    static func length(_ p: Product.SubscriptionPeriod) -> String {
        switch p.unit {
        case .day: return String(localized: "\(p.value)-day")
        case .week: return p.value == 1 ? String(localized: "7-day") : String(localized: "\(p.value)-week")
        case .month: return String(localized: "\(p.value)-month")
        case .year: return String(localized: "\(p.value)-year")
        @unknown default: return ""
        }
    }
}
