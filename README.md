# MoneyMCPServer

A companion tool for [Indigo Money](https://indigosoft.co.uk) by Indigosoft — available for iPhone, iPad, Mac, Apple Watch and Apple Vision Pro.

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that gives Claude access to your personal finance data from the app.

Ask Claude to analyse your spending, create transactions, track budgets, and more — all using the data you already have in Indigo Money.

[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26.0+-black?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![Tests](https://github.com/bolshedvorsky/money-mcp/actions/workflows/tests.yml/badge.svg)](https://github.com/bolshedvorsky/money-mcp/actions/workflows/tests.yml)

---

## Requirements

- macOS 26 or later
- [Indigo Money](https://indigosoft.co.uk) (iOS / macOS)
- [Claude Desktop](https://claude.ai/download) (or any MCP-compatible client)
- Swift 6.0+ (for building from source)

---

## Installation

### Build from source

```bash
git clone https://github.com/bolshedvorsky/money-mcp-server.git
cd money-mcp-server
swift build -c release
```

The compiled binary will be at `.build/release/MoneyMCPServer`. Copy it somewhere permanent:

```bash
cp .build/release/MoneyMCPServer /usr/local/bin/MoneyMCPServer
```

---

## Setup

### 1. Export your data from Money

Open the **Indigo Money** app on your iPhone or iPad, go to **Settings → Export for Claude**. This writes a snapshot of your data to:

```
~/Library/Application Support/MoneyMCPServer/data.json
```

Re-export whenever you want Claude to see your latest transactions.

### 2. Configure Claude Desktop

Edit the Claude Desktop config file at:

```
~/Library/Application Support/Claude/claude_desktop_config.json
```

Add the Money server under `mcpServers`:

```json
{
  "mcpServers": {
    "money": {
      "command": "/usr/local/bin/MoneyMCPServer"
    }
  }
}
```

Restart Claude Desktop. You should now be able to ask Claude about your finances.

### Custom data path

If you keep `data.json` somewhere else, set `MONEY_DATA_PATH`:

```json
{
  "mcpServers": {
    "money": {
      "command": "/usr/local/bin/MoneyMCPServer",
      "env": {
        "MONEY_DATA_PATH": "/path/to/data.json"
      }
    }
  }
}
```

---

## What you can ask Claude

Once connected, Claude can answer questions and take actions across all your Money data:

- *"How much did I spend on groceries last month?"*
- *"What's my current balance across all accounts?"*
- *"Show me my biggest expenses this year by category."*
- *"Create an expense of £45 at Tesco from my Checking account."*
- *"What's my monthly rent scheduled transaction?"*
- *"How much of my Food budget have I used this month?"*

---

## Available tools

### Accounts
| Tool | Description |
|------|-------------|
| `list_accounts` | List accounts with current balances, filter by type or active status |
| `get_account` | Get full details of a specific account |
| `create_account` | Create a new account (cash, bank, credit, loan, savings, etc.) |
| `update_account` | Update title, type, starting balance, active status, or sort order |
| `delete_account` | Delete an account (transactions are preserved) |

### Transactions
| Tool | Description |
|------|-------------|
| `list_transactions` | List transactions with filters: account, category, payee, type, date range, limit |
| `create_transaction` | Create an income, expense, or transfer transaction |
| `update_transaction` | Update any field on an existing transaction |
| `delete_transaction` | Delete a transaction |
| `get_spending_by_category` | Total expenses grouped by category for a date range |

### Budgets
| Tool | Description |
|------|-------------|
| `list_budgets` | List budgets with current spending and percentage used |
| `create_budget` | Create a budget for a category |
| `update_budget` | Update budget type or target amount |
| `delete_budget` | Delete a budget |

### Categories
| Tool | Description |
|------|-------------|
| `list_categories` | List all categories with parent/child relationships |
| `create_category` | Create a new category or subcategory |
| `update_category` | Update category title or icon |
| `delete_category` | Delete a category |

### Currencies
| Tool | Description |
|------|-------------|
| `list_currencies` | List currencies with exchange rates and account counts |
| `convert_amount` | Convert an amount between currencies using stored rates |
| `create_currency` | Add a new currency |
| `update_currency` | Update exchange rate or set as default |
| `delete_currency` | Remove a currency |

### Payees
| Tool | Description |
|------|-------------|
| `list_payees` | List payees, searchable by name |
| `create_payee` | Add a new payee |
| `update_payee` | Rename a payee |
| `delete_payee` | Remove a payee |

### Scheduled transactions
| Tool | Description |
|------|-------------|
| `list_scheduled_transactions` | List upcoming scheduled transactions, filter by date range |
| `create_scheduled_transaction` | Create a recurring transaction (daily, weekly, monthly, etc.) |
| `update_scheduled_transaction` | Update any field on a scheduled transaction |
| `delete_scheduled_transaction` | Remove a scheduled transaction |

---

## Data model

The server reads and writes the native Money app JSON export format, so no data conversion or separate database is needed. Changes made via MCP tools are written back to `data.json` immediately and will be reflected the next time you import the file into Money.

Account balances are computed dynamically from the starting balance plus all recorded transactions — exactly as the Money app calculates them.

---

## Development

### Run tests

```bash
swift test
```

Tests cover JSON parsing, balance computation, title denormalization, CRUD operations, and round-trip fidelity for all entity types.
