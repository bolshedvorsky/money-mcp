import Foundation
import MCP

enum BudgetTools {
    static let names: Set<String> = [
        "list_budgets",
        "create_budget", "update_budget", "delete_budget"
    ]

    static var definitions: [Tool] {
        [
            Tool(
                name: "list_budgets",
                description: "List all budgets showing category, target amount, current spending, and percentage used. Budget type is 'income' or 'expense'.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "type": ["type": "string", "description": "Filter by budget type: income or expense."],
                        "over_budget_only": ["type": "boolean", "description": "Only return budgets where current >= target."]
                    ]
                ]
            ),
            Tool(
                name: "create_budget",
                description: "Create a new budget for a category.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "type": ["type": "string", "description": "Budget type: income or expense."],
                        "category_id": ["type": "string", "description": "Category ID this budget applies to."],
                        "target": ["type": "number", "description": "Target amount for this budget period."]
                    ],
                    "required": ["type", "category_id", "target"]
                ]
            ),
            Tool(
                name: "update_budget",
                description: "Update an existing budget. Only supplied fields are changed.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Budget ID to update."],
                        "type": ["type": "string", "description": "New budget type: income or expense."],
                        "target": ["type": "number", "description": "New target amount."]
                    ],
                    "required": ["id"]
                ]
            ),
            Tool(
                name: "delete_budget",
                description: "Delete a budget by ID.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Budget ID to delete."]
                    ],
                    "required": ["id"]
                ]
            )
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, provider: DataProvider) throws -> [Tool.Content] {
        switch name {
        case "list_budgets":
            var budgets = provider.budgets()
            if let type = arguments?["type"]?.stringValue {
                budgets = budgets.filter { $0.type == type }
            }
            if arguments?["over_budget_only"]?.boolValue == true {
                budgets = budgets.filter { $0.current >= $0.target }
            }
            return [.text(text: prettyJSON(budgets), annotations: nil, _meta: nil)]

        case "create_budget":
            guard
                let type = arguments?["type"]?.stringValue,
                let categoryId = arguments?["category_id"]?.stringValue,
                let targetV = arguments?["target"],
                let target = Double(targetV)
            else { throw MCPError.invalidParams("Missing required parameters: type, category_id, target") }

            let budget = try provider.createBudget(type: type, categoryId: categoryId, target: target)
            return [.text(text: prettyJSON(budget), annotations: nil, _meta: nil)]

        case "update_budget":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            let budget = try provider.updateBudget(
                id: id,
                type: arguments?["type"]?.stringValue,
                target: arguments?["target"].flatMap { Double($0) }
            )
            return [.text(text: prettyJSON(budget), annotations: nil, _meta: nil)]

        case "delete_budget":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            try provider.deleteBudget(id: id)
            return [.text(text: "Budget deleted: \(id)", annotations: nil, _meta: nil)]

        default:
            throw MCPError.methodNotFound(name)
        }
    }
}
