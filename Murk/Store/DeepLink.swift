import Foundation

/// Where a `murk://` link leads. Add a case and a host name here to support a new destination.
enum DeepLink: Equatable {
    case page(Int)
    case settings

    static let scheme = "murk"
    private static let pages = ["now": 0, "air": 1, "rain": 2, "sun": 3, "moon": 4]

    /// Returns nil for anything that isn't a Murk link Murk understands.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // murk://air and murk:air and murk:///air all mean the same thing.
        let host = url.host ?? ""
        let name = (host.isEmpty ? (url.path.split(separator: "/").first.map(String.init) ?? "") : host).lowercased()
        if name == "settings" { self = .settings; return }
        guard let page = Self.pages[name] else { return nil }
        self = .page(page)
    }

    var url: URL {
        switch self {
        case .settings: return URL(string: "murk://settings")!
        case .page(let i): return URL(string: "murk://\(Self.pages.first { $0.value == i }?.key ?? "now")")!
        }
    }
}
