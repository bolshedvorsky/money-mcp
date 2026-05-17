import Foundation
import MCP

enum ScheduledTransactionTools {
    static let names: Set<String> = [
        "list_scheduled_transactions",
        "create_scheduled_transaction", "update_scheduled_transaction", "delete_scheduled_transaction",
    ]

    static var definitions: [Tool] {
        [
            Tool(
                name: "list_scheduled_transactions",
                description: "List upcoming recurring or one-off scheduled transactions. Intervals: never, daily, weekly, week2, week4, monthly, quarterly, yearly.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "from_date":      ["type": "string",  "description": "Start date in ISO 8601 format. Defaults to today."],
                        "to_date":        ["type": "string",  "description": "End date in ISO 8601 format."],
                        "type":           ["type": "string",  "description": "Filter by type: income, expense, or transfer."],
                        "automatic_only": ["type": "boolean", "description": "Only return auto-applied scheduled transactions."],
                    ],
                ]
            ),
            Tool(
                name: "create_scheduled_transaction",
                description: "Create a new scheduled or recurring transaction.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "value":                  ["type": "number",  "description": "Transaction amount."],
                        "currency_id":            ["type": "string",  "description": "ISO 4217 currency code."],
                        "type":                   ["type": "string",  "description": "Transaction type: income, expense, or transfer."],
                        "account_id":             ["type": "string",  "description": "Source account ID."],
                        "destination_account_id": ["type": "string",  "description": "Destination account ID (for transfers)."],
                        "date_scheduled":         ["type": "string",  "description": "Scheduled date in ISO 8601 format."],
                        "interval":               ["type": "string",  "description": "Recurrence interval: never, daily, weekly, week2, week4, monthly, quarterly, yearly."],
                        "is_automatic":           ["type": "boolean", "description": "Auto-apply when due. Defaults to false."],
                        "payee_id":               ["type": "string",  "description": "Payee ID."],
                        "category_id":            ["type": "string",  "description": "Category ID."],
                    ],
                    "required": ["value", "currency_id", "type", "account_id", "date_scheduled", "interval"],
                ]
            ),
            Tool(
                name: "update_scheduled_transaction",
                description: "Update fields on an existing scheduled transaction. Only supplied fields are changed.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id":                     ["type": "string",  "description": "Scheduled transaction ID to update."],
                        "value":                  ["type": "number",  "description": "New amount."],
                        "currency_id":            ["type": "string",  "description": "New currency code."],
                        "type":                   ["type": "string",  "description": "New transaction type."],
                        "account_id":             ["type": "string",  "description": "New source account ID."],
                        "destination_account_id": ["type": "string",  "description": "New destination account ID."],
                        "date_scheduled":         ["type": "string",  "description": "New scheduled date in ISO 8601 format."],
                        "interval":               ["type": "string",  "description": "New recurrence interval."],
                        "is_automatic":           ["type": "boolean", "description": "New auto-apply setting."],
                        "payee_id":               ["type": "string",  "description": "New payee ID."],
                        "category_id":            ["type": "string",  "description": "New category ID."],
                    ],
                    "required": ["id"],
                ]
            ),
            Tool(
                name: "delete_scheduled_transaction",
                description: "Delete a scheduled transaction by ID.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Scheduled transaction ID to delete."],
                    ],
                    "required": ["id"],
                ]
            ),
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, provider: DataProvider) throws -> [Tool.Content] {
        switch name {
        case "list_scheduled_transactions":
            var results = provider.scheduledTransactions(
                from: arguments?["from_date"]?.stringValue.flatMap(parseDate) ?? Date(),
                to:   arguments?["to_date"]?.stringValue.flatMap(parseDate)
            )
            if let type = arguments?["type"]?.stringValue         { results = results.filter { $0.type == type } }
            if arguments?["automatic_only"]?.boolValue == true    { results = results.filter { $0.isAutomatic } }
            return [.text(text: prettyJSON(results), annotations: nil, _meta: nil)]

        case "create_scheduled_transaction":
            guard
                let valueV        = arguments?["value"], let value = Double(valueV),
                let currencyId    = arguments?["currency_id"]?.stringValue,
                let type          = arguments?["type"]?.stringValue,
                let accountId     = arguments?["account_id"]?.stringValue,
                let dateStr       = arguments?["date_scheduled"]?.stringValue,
                let dateScheduled = parseDate(dateStr),
                let interval      = arguments?["interval"]?.stringValue
            else { throw MCPError.invalidParams("Missing required parameters: value, currency_id, type, account_id, date_scheduled, interval") }
            let s = try provider.createScheduledTransaction(
                value: value, currencyId: currencyId, type: type,
                accountId: accountId,
                destinationAccountId: arguments?["destination_account_id"]?.stringValue,
                dateScheduled: dateScheduled, interval: interval,
                isAutomatic: arguments?["is_automatic"]?.boolValue ?? false,
                payeeId:    arguments?["payee_id"]?.stringValue,
                categoryId: arguments?["category_id"]?.stringValue
            )
            return [.text(text: prettyJSON(s), annotations: nil, _meta: nil)]

        case "update_scheduled_transaction":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }
            let s = try provider.updateScheduledTransaction(
                id: id,
                value:                arguments?["value"].flatMap { Double($0) },
                currencyId:           arguments?["currency_id"]?.stringValue,
                type:                 arguments?["type"]?.stringValue,
                accountId:            arguments?["account_id"]?.stringValue,
                destinationAccountId: arguments?["destination_account_id"]?.stringValue,
                dateScheduled:        arguments?["date_scheduled"]?.stringValue.flatMap(parseDate),
                interval:             arguments?["interval"]?.stringValue,
                isAutomatic:          arguments?["is_automatic"]?.boolValue,
                payeeId:              arguments?["payee_id"]?.stringValue,
                categoryId:           arguments?["category_id"]?.stringValue
            )
            return [.text(text: prettyJSON(s), annotations: nil, _meta: nil)]

        case "delete_scheduled_transaction":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }
            try provider.deleteScheduledTransaction(id: id)
            return [.text(text: "Scheduled transaction deleted: \(id)", annotations: nil, _meta: nil)]

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
