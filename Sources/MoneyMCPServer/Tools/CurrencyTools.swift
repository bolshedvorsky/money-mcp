import Foundation
import MCP

enum CurrencyTools {
    static let names: Set<String> = [
        "list_currencies", "convert_amount",
        "create_currency", "update_currency", "delete_currency"
    ]

    static var definitions: [Tool] {
        [
            Tool(
                name: "list_currencies",
                description: "List all currencies in the Money app, including exchange rates relative to the default currency.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "active_only": ["type": "boolean", "description": "Only return currencies used by at least one account."]
                    ]
                ]
            ),
            Tool(
                name: "convert_amount",
                description: "Convert an amount between currencies using stored exchange rates.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "amount": ["type": "number", "description": "Amount to convert."],
                        "from": ["type": "string", "description": "Source currency code, e.g. USD."],
                        "to": ["type": "string", "description": "Target currency code, e.g. EUR."]
                    ],
                    "required": ["amount", "from", "to"]
                ]
            ),
            Tool(
                name: "create_currency",
                description: "Add a new currency. The exchange rate is relative to the default currency (default currency has rate 1.0).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "ISO 4217 currency code, e.g. JPY."],
                        "exchange_rate": ["type": "number", "description": "Exchange rate relative to the default currency."],
                        "is_default": ["type": "boolean", "description": "Set as the default currency. Clears the existing default. Defaults to false."]
                    ],
                    "required": ["id", "exchange_rate"]
                ]
            ),
            Tool(
                name: "update_currency",
                description: "Update a currency's exchange rate or default status.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Currency code to update."],
                        "exchange_rate": ["type": "number", "description": "New exchange rate."],
                        "is_default": ["type": "boolean", "description": "Set as the default currency."]
                    ],
                    "required": ["id"]
                ]
            ),
            Tool(
                name: "delete_currency",
                description: "Delete a currency by its ISO code.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Currency code to delete, e.g. USD."]
                    ],
                    "required": ["id"]
                ]
            )
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, provider: DataProvider) throws -> [Tool.Content] {
        switch name {
        case "list_currencies":
            var currencies = provider.currencies()
            if arguments?["active_only"]?.boolValue == true {
                currencies = currencies.filter { $0.accountsCount > 0 }
            }
            return [.text(text: prettyJSON(currencies), annotations: nil, _meta: nil)]

        case "convert_amount":
            guard
                let amountV = arguments?["amount"], let amount = Double(amountV),
                let from = arguments?["from"]?.stringValue,
                let to = arguments?["to"]?.stringValue
            else { throw MCPError.invalidParams("Missing required parameters: amount, from, to") }

            if from == to {
                return [.text(text: "\(amount) \(to)", annotations: nil, _meta: nil)]
            }
            guard let rate = provider.exchangeRate(from: from, to: to) else {
                return [.text(text: "Exchange rate not available for \(from) → \(to)", annotations: nil, _meta: nil)]
            }

            let result: [String: String] = ["from": "\(amount) \(from)", "to": "\(amount * rate) \(to)", "rate": "\(rate)"]
            return [.text(text: prettyJSON(result), annotations: nil, _meta: nil)]

        case "create_currency":
            guard
                let id = arguments?["id"]?.stringValue,
                let rateV = arguments?["exchange_rate"],
                let exchangeRate = Double(rateV)
            else { throw MCPError.invalidParams("Missing required parameters: id, exchange_rate") }

            let currency = try provider.createCurrency(
                id: id, exchangeRate: exchangeRate,
                isDefault: arguments?["is_default"]?.boolValue ?? false
            )
            return [.text(text: prettyJSON(currency), annotations: nil, _meta: nil)]

        case "update_currency":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            let currency = try provider.updateCurrency(
                id: id,
                exchangeRate: arguments?["exchange_rate"].flatMap { Double($0) },
                isDefault: arguments?["is_default"]?.boolValue
            )
            return [.text(text: prettyJSON(currency), annotations: nil, _meta: nil)]

        case "delete_currency":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            try provider.deleteCurrency(id: id)
            return [.text(text: "Currency deleted: \(id)", annotations: nil, _meta: nil)]

        default:
            throw MCPError.methodNotFound(name)
        }
    }
}
