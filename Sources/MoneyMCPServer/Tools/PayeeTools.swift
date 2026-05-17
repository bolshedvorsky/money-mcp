import Foundation
import MCP

enum PayeeTools {
    static let names: Set<String> = [
        "list_payees",
        "create_payee", "update_payee", "delete_payee",
    ]

    static var definitions: [Tool] {
        [
            Tool(
                name: "list_payees",
                description: "List payees (merchants, people, or businesses associated with transactions). Sorted alphabetically.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search payees by name (case-insensitive substring match)."],
                    ],
                ]
            ),
            Tool(
                name: "create_payee",
                description: "Create a new payee.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Payee name."],
                    ],
                    "required": ["title"],
                ]
            ),
            Tool(
                name: "update_payee",
                description: "Rename a payee.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id":    ["type": "string", "description": "Payee ID to update."],
                        "title": ["type": "string", "description": "New payee name."],
                    ],
                    "required": ["id", "title"],
                ]
            ),
            Tool(
                name: "delete_payee",
                description: "Delete a payee by ID.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Payee ID to delete."],
                    ],
                    "required": ["id"],
                ]
            ),
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, provider: DataProvider) throws -> [Tool.Content] {
        switch name {
        case "list_payees":
            let payees = provider.payees(query: arguments?["query"]?.stringValue)
            return [.text(text: prettyJSON(payees), annotations: nil, _meta: nil)]

        case "create_payee":
            guard let title = arguments?["title"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: title")
            }
            let payee = try provider.createPayee(title: title)
            return [.text(text: prettyJSON(payee), annotations: nil, _meta: nil)]

        case "update_payee":
            guard
                let id    = arguments?["id"]?.stringValue,
                let title = arguments?["title"]?.stringValue
            else { throw MCPError.invalidParams("Missing required parameters: id, title") }
            let payee = try provider.updatePayee(id: id, title: title)
            return [.text(text: prettyJSON(payee), annotations: nil, _meta: nil)]

        case "delete_payee":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }
            try provider.deletePayee(id: id)
            return [.text(text: "Payee deleted: \(id)", annotations: nil, _meta: nil)]

        default:
            throw MCPError.methodNotFound(name)
        }
    }
}
