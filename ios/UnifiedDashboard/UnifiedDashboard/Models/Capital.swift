import Foundation

// MARK: - /api/capital response

struct CapitalResponse: Codable {
    let realBalance: Int?
    let totalAllocated: Int
    let unallocated: Int?
    let accounts: [CapitalAccount]

    enum CodingKeys: String, CodingKey {
        case realBalance = "real_balance"
        case totalAllocated = "total_allocated"
        case unallocated
        case accounts
    }
}

struct CapitalAccount: Codable, Identifiable {
    let id: String
    let label: String
    let allocation: Int   // cents
    let pnl: Int          // cents
    let effective: Int     // cents
    let color: String
}

// MARK: - /api/capital/transfers response

struct TransfersResponse: Codable {
    let transfers: [Transfer]
}

struct Transfer: Codable, Identifiable {
    /// Stored unique ID combining all fields + a UUID suffix to prevent collisions
    /// on same-second, same-amount transfers between the same accounts.
    let id: String

    let from: String
    let to: String
    let amount: Int   // cents
    let ts: String

    enum CodingKeys: String, CodingKey {
        case from, to, amount, ts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.from   = try container.decode(String.self, forKey: .from)
        self.to     = try container.decode(String.self, forKey: .to)
        self.amount = try container.decode(Int.self,    forKey: .amount)
        self.ts     = try container.decode(String.self, forKey: .ts)
        let suffix  = UUID().uuidString.prefix(8)
        self.id     = "\(self.from)-\(self.to)-\(self.ts)-\(self.amount)-\(suffix)"
    }
}

// MARK: - Request bodies

struct AllocateRequest: Encodable {
    let botId: String
    let label: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case botId = "bot_id"
        case label, amount
    }
}

struct TransferRequest: Encodable {
    let from: String
    let to: String
    let amount: Double
}
