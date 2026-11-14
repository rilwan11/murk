import Foundation
import StoreKit

/// The facts about a subscription transaction that decide access.
struct ProTransaction: Equatable {
    var productID: String
    var expirationDate: Date?
    var revocationDate: Date?
    var isUpgraded = false
}

/// Pure rules for "is this person a Murk Pro subscriber right now".
enum ProStatus {
    static let monthlyID = "com.rilwan11.murk.pro.monthly"
    static let annualID = "com.rilwan11.murk.pro.annual"
    static let productIDs: Set<String> = [monthlyID, annualID]
    static let groupName = "Murk Pro"
    /// Last confirmed state, so Pro features are there at launch before the App Store answers.
    static let cacheKey = "pro.cached"

    static func isActive(_ transactions: [ProTransaction], now: Date = Date()) -> Bool {
        transactions.contains { t in
            guard productIDs.contains(t.productID), t.revocationDate == nil, !t.isUpgraded else { return false }
            if let end = t.expirationDate { return end > now }
            return true
        }
    }
}

/// Watches the App Store for the Murk Pro subscription and exposes `isPro`.
/// No account or sign-in: purchases belong to the Apple ID and restore on any device.
@MainActor
final class EntitlementStore: ObservableObject {
    @Published private(set) var isPro: Bool
    @Published private(set) var products: [Product] = []
    @Published private(set) var loadFailed = false
    @Published private(set) var isWorking = false
    @Published var message: String?
    /// Whether the annual plan's free trial is still available to this Apple ID.
    @Published private(set) var trialEligible = false

    /// Told about every confirmed change, so features unlock or lock immediately.
    var onChange: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private var updates: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPro = defaults.bool(forKey: ProStatus.cacheKey)
    }

    func start() {
        guard updates == nil else { return }
        // Renewals, expirations, refunds and purchases made elsewhere arrive here.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh(); await loadProducts() }
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: ProStatus.productIDs)
            products = list.sorted { $0.price < $1.price }
            loadFailed = list.isEmpty
            if let annual = list.first(where: { $0.id == ProStatus.annualID }), let sub = annual.subscription {
                trialEligible = await sub.isEligibleForIntroOffer
            }
        } catch {
            loadFailed = true
        }
    }

    /// Re-reads the current, verified entitlements.
    func refresh() async {
        var list: [ProTransaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }      // unverified transactions grant nothing
            list.append(ProTransaction(productID: t.productID, expirationDate: t.expirationDate,
                                       revocationDate: t.revocationDate, isUpgraded: t.isUpgraded))
        }
        apply(ProStatus.isActive(list))
    }

    func apply(_ pro: Bool) {
        var value = pro
        #if DEBUG
        if defaults.bool(forKey: "debug.unlockPro") { value = true }
        #endif
        defaults.set(value, forKey: ProStatus.cacheKey)
        if value != isPro { isPro = value }
        onChange?(value)
    }

    func purchase(_ product: Product) async {
        isWorking = true; message = nil
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    await refresh()
                } else {
                    message = String(localized: "The purchase couldn't be verified. You haven't been charged for Murk Pro access.")
                }
            case .pending:
                message = String(localized: "Your purchase is waiting for approval. Murk Pro unlocks as soon as it's approved.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = String(localized: "The purchase didn't go through. Check your connection and try again.")
        }
    }

    func restore() async {
        isWorking = true; message = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refresh()
            message = isPro ? String(localized: "Murk Pro restored.") : String(localized: "No Murk Pro subscription was found for this Apple ID.")
        } catch {
            message = String(localized: "Couldn't reach the App Store. Try again in a moment.")
        }
    }

    #if DEBUG
    var debugUnlock: Bool {
        get { defaults.bool(forKey: "debug.unlockPro") }
        set { defaults.set(newValue, forKey: "debug.unlockPro"); Task { await refresh() } }
    }
    #endif
}
