import Foundation
import MCP

enum AccountTools {
    static let names: Set<String> = [
        "list_accounts", "get_account",
        "create_account", "update_account", "delete_account",
    ]

    static var definitions: [Tool] {
        [
            Tool(
                name: "list_accounts",
                description: "List financial accounts with their current balances. Account types: cash, bank, credit, loan, mortgage, asset, savings, investment.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "active_only": ["type": "boolean", "description": "Only return active accounts. Defaults to true."],
                        "type": ["type": "string", "description": "Filter by account type: cash, bank, credit, loan, mortgage, asset, savings, investment."],
                    ],
                ]
            ),
            Tool(
                name: "get_account",
                description: "Get full details of a specific account by its ID.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Account ID."],
                    ],
                    "required": ["id"],
                ]
            ),
            Tool(
                name: "create_account",
                description: "Create a new financial account.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Account name."],
                        "type": ["type": "string", "description": "Account type: cash, bank, credit, loan, mortgage, asset, savings, investment."],
                        "currency_id": ["type": "string", "description": "ISO 4217 currency code, e.g. USD."],
                        "start_balance": ["type": "number", "description": "Opening balance. Defaults to 0."],
                        "group_id": ["type": "string", "description": "Account group ID. Leave empty for default group."],
                    ],
                    "required": ["title", "type", "currency_id"],
                ]
            ),
            Tool(
                name: "update_account",
                description: "Update fields on an existing account. Only supplied fields are changed.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Account ID to update."],
                        "title": ["type": "string", "description": "New account name."],
                        "type": ["type": "string", "description": "New account type."],
                        "is_active": ["type": "boolean", "description": "Set active/inactive."],
                        "group_id": ["type": "string", "description": "New group ID."],
                        "sort_order": ["type": "integer", "description": "Display sort position."],
                        "start_balance": ["type": "number", "description": "New opening balance (also updates current balance)."],
                    ],
                    "required": ["id"],
                ]
            ),
            Tool(
                name: "delete_account",
                description: "Delete an account by ID. This does not delete associated transactions.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Account ID to delete."],
                    ],
                    "required": ["id"],
                ]
            ),
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, provider: DataProvider) throws -> [Tool.Content] {
        switch name {
        case "list_accounts":
            let accounts = provider.accounts(
                activeOnly: arguments?["active_only"]?.boolValue ?? true,
                type: arguments?["type"]?.stringValue
            )
            return [.text(text: prettyJSON(accounts), annotations: nil, _meta: nil)]

        case "get_account":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }
            guard let account = provider.account(id: id) else {
                return [.text(text: "No account found with id: \(id)", annotations: nil, _meta: nil)]
            }
            return [.text(text: prettyJSON(account), annotations: nil, _meta: nil)]

        case "create_account":
            guard
                let title      = arguments?["title"]?.stringValue,
                let type       = arguments?["type"]?.stringValue,
                let currencyId = arguments?["currency_id"]?.stringValue
            else { throw MCPError.invalidParams("Missing required parameters: title, type, currency_id") }
            let balance = arguments?["start_balance"].flatMap { Double($0) } ?? 0
            let groupId = arguments?["group_id"]?.stringValue ?? ""
            let account = try provider.createAccount(title: title, type: type, currencyId: currencyId, startBalance: balance, groupId: groupId)
            return [.text(text: prettyJSON(account), annotations: nil, _meta: nil)]

        case "update_account":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }
            let account = try provider.updateAccount(
                id: id,
                title:       arguments?["title"]?.stringValue,
                type:        arguments?["type"]?.stringValue,
                isActive:    arguments?["is_active"]?.boolValue,
                groupId:     arguments?["group_id"]?.stringValue,
                sortOrder:   arguments?["sort_order"]?.intValue,
                startBalance: arguments?["start_balance"].flatMap { Double($0) }
            )
            return [.text(text: prettyJSON(account), annotations: nil, _meta: nil)]

        case "delete_account":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }
            try provider.deleteAccount(id: id)
            return [.text(text: "Account deleted: \(id)", annotations: nil, _meta: nil)]

        default:
            throw MCPError.methodNotFound(name)
        }
    }
}
