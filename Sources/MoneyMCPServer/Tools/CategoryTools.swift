import Foundation
import MCP

enum CategoryTools {
    static let names: Set<String> = [
        "list_categories",
        "create_category", "update_category", "delete_category"
    ]

    static var definitions: [Tool] {
        [
            Tool(
                name: "list_categories",
                description: "List all transaction categories. Categories are hierarchical — top-level categories have an empty parentId. Each includes its SF Symbol image name and usage count.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "parent_id": ["type": "string", "description": "Return only children of this parent category ID."],
                        "top_level_only": ["type": "boolean", "description": "Return only top-level (root) categories."]
                    ]
                ]
            ),
            Tool(
                name: "create_category",
                description: "Create a new transaction category. Optionally nest it under an existing parent category.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Category name."],
                        "image_name": ["type": "string", "description": "SF Symbol name for the icon. Defaults to 'tag'."],
                        "parent_id": ["type": "string", "description": "Parent category ID for sub-categories. Omit for top-level."]
                    ],
                    "required": ["title"]
                ]
            ),
            Tool(
                name: "update_category",
                description: "Update an existing category's name or icon.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Category ID to update."],
                        "title": ["type": "string", "description": "New category name."],
                        "image_name": ["type": "string", "description": "New SF Symbol name."]
                    ],
                    "required": ["id"]
                ]
            ),
            Tool(
                name: "delete_category",
                description: "Delete a category by ID.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "Category ID to delete."]
                    ],
                    "required": ["id"]
                ]
            )
        ]
    }

    static func handle(name: String, arguments: [String: Value]?, provider: DataProvider) throws -> [Tool.Content] {
        switch name {
        case "list_categories":
            var categories = provider.categories()
            if let parentId = arguments?["parent_id"]?.stringValue {
                categories = categories.filter { $0.parentId == parentId }
            } else if arguments?["top_level_only"]?.boolValue == true {
                categories = categories.filter { $0.parentId.isEmpty }
            }
            return [.text(text: prettyJSON(categories), annotations: nil, _meta: nil)]

        case "create_category":
            guard let title = arguments?["title"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: title")
            }

            let category = try provider.createCategory(
                title: title,
                imageName: arguments?["image_name"]?.stringValue,
                parentId: arguments?["parent_id"]?.stringValue
            )
            return [.text(text: prettyJSON(category), annotations: nil, _meta: nil)]

        case "update_category":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            let category = try provider.updateCategory(
                id: id,
                title: arguments?["title"]?.stringValue,
                imageName: arguments?["image_name"]?.stringValue
            )
            return [.text(text: prettyJSON(category), annotations: nil, _meta: nil)]

        case "delete_category":
            guard let id = arguments?["id"]?.stringValue else {
                throw MCPError.invalidParams("Missing required parameter: id")
            }

            try provider.deleteCategory(id: id)
            return [.text(text: "Category deleted: \(id)", annotations: nil, _meta: nil)]

        default:
            throw MCPError.methodNotFound(name)
        }
    }
}
