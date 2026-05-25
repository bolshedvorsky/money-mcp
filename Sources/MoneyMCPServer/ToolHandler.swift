import Foundation
import MCP

struct ToolHandler {
    let provider: DataProvider

    var allDefinitions: [Tool] {
        AccountTools.definitions +
            TransactionTools.definitions +
            BudgetTools.definitions +
            CategoryTools.definitions +
            CurrencyTools.definitions +
            PayeeTools.definitions +
            ScheduledTransactionTools.definitions
    }

    func handle(name: String, arguments: [String: Value]?) throws -> [Tool.Content] {
        switch name {
        case _ where AccountTools.names.contains(name):
            return try AccountTools.handle(name: name, arguments: arguments, provider: provider)
        case _ where TransactionTools.names.contains(name):
            return try TransactionTools.handle(name: name, arguments: arguments, provider: provider)
        case _ where BudgetTools.names.contains(name):
            return try BudgetTools.handle(name: name, arguments: arguments, provider: provider)
        case _ where CategoryTools.names.contains(name):
            return try CategoryTools.handle(name: name, arguments: arguments, provider: provider)
        case _ where CurrencyTools.names.contains(name):
            return try CurrencyTools.handle(name: name, arguments: arguments, provider: provider)
        case _ where PayeeTools.names.contains(name):
            return try PayeeTools.handle(name: name, arguments: arguments, provider: provider)
        case _ where ScheduledTransactionTools.names.contains(name):
            return try ScheduledTransactionTools.handle(name: name, arguments: arguments, provider: provider)
        default:
            throw MCPError.methodNotFound(name)
        }
    }
}
