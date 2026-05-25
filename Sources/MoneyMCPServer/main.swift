import Foundation
import MCP

Task {
    do {
        let dataURL = resolveDataURL()

        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            fputs("""
            Error: snapshot file not found at \(dataURL.path)
            Export data from the Money app first (Settings → Export for MCP).
            You can also set MONEY_DATA_PATH to a custom path.\n
            """, stderr)
            exit(1)
        }

        let provider = try JSONDataProvider(url: dataURL)
        let handler = ToolHandler(provider: provider)

        let server = Server(
            name: "money",
            version: "1.0.0",
            capabilities: Server.Capabilities(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: handler.allDefinitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let content = try handler.handle(name: params.name, arguments: params.arguments)
                return CallTool.Result(content: content)
            } catch let error as MCPError {
                throw error
            } catch {
                return CallTool.Result(
                    content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    } catch {
        fputs("Fatal: \(error)\n", stderr)
        exit(1)
    }
}

dispatchMain()

// MARK: -

private func resolveDataURL() -> URL {
    if let custom = ProcessInfo.processInfo.environment["MONEY_DATA_PATH"] {
        return URL(fileURLWithPath: custom)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MoneyMCPServer/data.json")
}
