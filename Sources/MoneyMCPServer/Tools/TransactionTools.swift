import Foundation
import MCP

enum TransactionTools {
    static let names: Set<String> = [
        "list_transactions", "get_spending_by_category",
        "create_transaction", "update_transaction", "delete_transaction",
        "set_transactions_reconciled"
    ]

    static var definitions: [Tool] {
        [
            Tool(
                name: "list_transactions",
                description: "List transactions with optional filters. Returns results sorted by date descending.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "account_id": ["type": "string", "description": "Filter by source or destination account ID."],
                        "category_id": ["type": "string", "description": "Filter by category ID."],
                        "payee_id": ["type": "string", "description": "Filter by payee ID."],
                        "type": ["type": "string", "description": "Transaction type: income, expense, or transfer."],
                        "from_date": ["type": "string", "description": "Start date in ISO 8601 format (e.g. 2025-01-01)."],
                        "to_date": ["type": "string", "description": "End date in ISO 8601 format."],
                        "reconciled": ["type": "boolean", "description": "Filter by reconciliation status: true for reconciled transactions only, false for unreconciled only."],
                        "limit": ["type": "integer", "description": "Maximum results to return. Defaults to 50."]
                    ]
                ]
            ),
            Tool(
                name: "get_spending_by_category",
                description: "Aggregate total expenses grouped by category for a given date range.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "from_date": ["type": "string", "description": "Start date in ISO 8601 format."],
                        "to_date": ["type": "string", "description": "End date in ISO 8601 format."]
                    ]
                ]
            ),
            Tool(
                name: "create_transaction",
                description: "Create a new transaction. Updates the source account balance automatically.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "value": ["type": "number", "description": "Transaction amount (positive number)."],
                        "currency_id": ["type": "string", "description": "ISO 4217 currency code, e.g. USD."],
                        "type": ["type": "string", "description": "Transaction type: income, expense, or transfer."],
                        "source_account_id": ["type": "string", "description": "Account where the transaction originates."],
                        "destination_account_id": ["type": "string", "description": "Destination account ID (required for transfers)."],
                        "payee_id": ["type": "string", "description": "Payee ID."],
                        "category_id": ["type": "string", "description": "Category ID."],
                        "notes": ["type": "string", "description": "Optional notes."],
                        "date": ["type": "string", "description": "Transaction date in ISO 8601 format. Defaults to now."],
                        "reconciled": ["type": "boolean", "description": "Whether the transaction is reconciled against a bank statement. Defaults to false."]
                    ],
                    "required": ["value", "currency_id", "type", "source_account_id"]
                ]
            ),
            Tool(
                name: "update_transaction",
                description: "Update fields on an existing transaction. Balance adjustments are applied automatically.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Transaction ID to update."],
                        "value": ["type": "number", "description": "New transaction amount."],
                        "currency_id": ["type": "string", "description": "New currency code."],
                        "type": ["type": "string", "description": "New transaction type: income, expense, or transfer."],
                        "source_account_id": ["type": "string", "description": "New source account ID."],
                        "destination_account_id": ["type": "string", "description": "New destination account ID."],
                        "payee_id": ["type": "string", "description": "New payee ID."],
                        "category_id": ["type": "string", "description": "New category ID."],
                        "notes": ["type": "string", "description": "New notes."],
                        "reconciled": ["type": "boolean", "description": "Whether the transaction is reconciled against a bank statement."]
                    ],
                    "required": ["id"]
                ]
            ),
            Tool(
                name: "delete_transaction",
                description: "Delete a transaction by ID. Reverses its effect on the account balance.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Transaction ID to delete."]
                    ],
                    "required": ["id"]
                ]
            ),
            Tool(
                name: "set_transactions_reconciled",
                description: "Mark one or more transactions as reconciled or unreconciled against a bank statement, e.g. when matching transactions during a reconciliation pass.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "ids": ["type": "array", "items": ["type": "string"], "description": "Transaction IDs to update."],
                        "reconciled": ["type": "boolean", "description": "Reconciliation status to apply to all listed transactions."]
                    ],
                    "required": ["ids", "reconciled"]
                ]
            )
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, provider: DataProvider) throws -> [Tool.Content] {
        switch name {
        case "list_transactions":
            let results = provider.transactions(
                accountId: arguments?["account_id"]?.stringValue,
                categoryId: arguments?["category_id"]?.stringValue,
                payeeId: arguments?["payee_id"]?.stringValue,
                type: arguments?["type"]?.stringValue,
                from: arguments?["from_date"]?.stringValue.flatMap(parseDate),
                to: arguments?["to_date"]?.stringValue.flatMap(parseDate),
                reconciled: arguments?["reconciled"]?.boolValue,
                limit: arguments?["limit"]?.intValue ?? 50
            )
            return [.text(text: prettyJSON(results), annotations: nil, _meta: nil)]

        case "get_spending_by_category":
            let breakdown = provider.spendingByCategory(
                from: arguments?["from_date"]?.stringValue.flatMap(parseDate),
                to: arguments?["to_date"]?.stringValue.flatMap(parseDate)
            )
            let output = breakdown.map { ["category": $0.category, "total": "\($0.total)"] }
            return [.text(text: prettyJSON(output), annotations: nil, _meta: nil)]

        case "create_transaction":
            guard
                let valueV = arguments?["value"],
                let value = Double(valueV),
                let currencyId = arguments?["currency_id"]?.stringValue,
                let type = arguments?["type"]?.stringValue,
                let sourceAccountId = arguments?["source_account_id"]?.stringValue
            else { throw MCPError.invalidParams("Missing required parameters: value, currency_id, type, source_account_id") }

            let t = try provider.createTransaction(
                value: value,
                currencyId: currencyId,
                type: type,
                sourceAccountId: sourceAccountId,
                destinationAccountId: arguments?["destination_account_id"]?.stringValue,
                payeeId: arguments?["payee_id"]?.stringValue,
                categoryId: arguments?["category_id"]?.stringValue,
                notes: arguments?["notes"]?.stringValue,
                dateCreated: arguments?["date"]?.stringValue.flatMap(parseDate),
                reconciled: arguments?["reconciled"]?.boolValue ?? false
            )
            return [.text(text: prettyJSON(t), annotations: nil, _meta: nil)]

        case "update_transaction":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            let t = try provider.updateTransaction(
                id: id,
                value: arguments?["value"].flatMap { Double($0) },
                currencyId: arguments?["currency_id"]?.stringValue,
                type: arguments?["type"]?.stringValue,
                sourceAccountId: arguments?["source_account_id"]?.stringValue,
                destinationAccountId: arguments?["destination_account_id"]?.stringValue,
                payeeId: arguments?["payee_id"]?.stringValue,
                categoryId: arguments?["category_id"]?.stringValue,
                notes: arguments?["notes"]?.stringValue,
                reconciled: arguments?["reconciled"]?.boolValue
            )
            return [.text(text: prettyJSON(t), annotations: nil, _meta: nil)]

        case "delete_transaction":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            try provider.deleteTransaction(id: id)
            return [.text(text: "Transaction deleted: \(id)", annotations: nil, _meta: nil)]

        case "set_transactions_reconciled":
            guard
                let ids = arguments?["ids"]?.arrayValue?.compactMap(\.stringValue), !ids.isEmpty,
                let reconciled = arguments?["reconciled"]?.boolValue
            else { throw MCPError.invalidParams("Missing required parameters: ids, reconciled") }

            let updated = try provider.setReconciled(ids: ids, reconciled: reconciled)
            return [.text(text: prettyJSON(updated), annotations: nil, _meta: nil)]

        default:
            throw MCPError.methodNotFound(name)
        }
    }
}

private func parseDate(_ string: String) -> Date? {
    let full = ISO8601DateFormatter()
    full.formatOptions = [.withFullDate]
    return full.date(from: string) ?? ISO8601DateFormatter().date(from: string)
}
