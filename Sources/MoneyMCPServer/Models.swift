import Foundation

// Standalone Codable models matching MoneyCore's exported JSON shape.
// The Money app encodes its models via JSONEncoder — field names match exactly.

struct MCPAccount: Codable {
    let id: String
    let title: String
    let type: String
    let balance: Double
    let startBalance: Double
    let currencyId: String
    let groupId: String
    let isActive: Bool
    let sortOrder: Int
    let transactionsCount: Int
}

struct MCPTransaction: Codable {
    let id: String
    let dateCreated: Date
    let value: Double
    let currencyId: String
    let exchangeValue: Double
    let exchangeCurrencyId: String
    let type: String
    let sourceAccountId: String
    let sourceAccountTitle: String
    let destinationAccountId: String
    let destinationAccountTitle: String
    let payeeId: String
    let payeeTitle: String
    let categoryId: String
    let categoryTitle: String
    let notes: String
}

struct MCPBudget: Codable {
    let id: String
    let type: String
    let categoryId: String
    let categoryTitle: String
    let categoryImageName: String
    let target: Double
    let current: Double
    let percentage: Double
}

struct MCPCategory: Codable {
    let id: String
    let title: String
    let imageName: String
    let parentId: String
    let parentTitle: String
    let transactionsCount: Int
}

struct MCPCurrency: Codable {
    let id: String
    let isDefault: Bool
    let exchangeRate: Double
    let accountsCount: Int
}

struct MCPPayee: Codable {
    let id: String
    let title: String
    let transactionsCount: Int
}

struct MCPScheduledTransaction: Codable {
    let id: String
    let value: Double
    let currencyId: String
    let type: String
    let dateScheduled: Date
    let interval: String
    let isAutomatic: Bool
    let accountId: String
    let accountTitle: String
    let destinationAccountId: String
    let destinationAccountTitle: String
    let payeeTitle: String
    let categoryTitle: String
}

// In-memory working model for the MCP server (not persisted directly).
struct MoneySnapshot {
    var accounts: [MCPAccount]
    var transactions: [MCPTransaction]
    var budgets: [MCPBudget]
    var categories: [MCPCategory]
    var currencies: [MCPCurrency]
    var payees: [MCPPayee]
    var scheduledTransactions: [MCPScheduledTransaction]
}
