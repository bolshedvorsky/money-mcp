import Foundation
import MCP

// MARK: - Protocol

protocol DataProvider: AnyObject, Sendable {
    // Accounts
    func accounts(activeOnly: Bool, type: String?) -> [MCPAccount]
    func account(id: String) -> MCPAccount?
    @discardableResult func createAccount(title: String, type: String, currencyId: String, startBalance: Double, groupId: String) throws -> MCPAccount
    @discardableResult func updateAccount(id: String, title: String?, type: String?, isActive: Bool?, groupId: String?, sortOrder: Int?, startBalance: Double?) throws -> MCPAccount
    func deleteAccount(id: String) throws

    // Transactions
    func transactions(accountId: String?, categoryId: String?, payeeId: String?, type: String?, from: Date?, to: Date?, limit: Int?) -> [MCPTransaction]
    func spendingByCategory(from: Date?, to: Date?) -> [(category: String, total: Double)]
    @discardableResult func createTransaction(value: Double, currencyId: String, type: String, sourceAccountId: String, destinationAccountId: String?, payeeId: String?, categoryId: String?, notes: String?, dateCreated: Date?) throws -> MCPTransaction
    @discardableResult func updateTransaction(id: String, value: Double?, currencyId: String?, type: String?, sourceAccountId: String?, destinationAccountId: String?, payeeId: String?, categoryId: String?, notes: String?) throws -> MCPTransaction
    func deleteTransaction(id: String) throws

    // Budgets
    func budgets() -> [MCPBudget]
    @discardableResult func createBudget(type: String, categoryId: String, target: Double) throws -> MCPBudget
    @discardableResult func updateBudget(id: String, type: String?, target: Double?) throws -> MCPBudget
    func deleteBudget(id: String) throws

    // Categories
    func categories() -> [MCPCategory]
    @discardableResult func createCategory(title: String, imageName: String?, parentId: String?) throws -> MCPCategory
    @discardableResult func updateCategory(id: String, title: String?, imageName: String?) throws -> MCPCategory
    func deleteCategory(id: String) throws

    // Currencies
    func currencies() -> [MCPCurrency]
    func defaultCurrency() -> MCPCurrency?
    func exchangeRate(from: String, to: String) -> Double?
    @discardableResult func createCurrency(id: String, exchangeRate: Double, isDefault: Bool) throws -> MCPCurrency
    @discardableResult func updateCurrency(id: String, exchangeRate: Double?, isDefault: Bool?) throws -> MCPCurrency
    func deleteCurrency(id: String) throws

    // Payees
    func payees(query: String?) -> [MCPPayee]
    @discardableResult func createPayee(title: String) throws -> MCPPayee
    @discardableResult func updatePayee(id: String, title: String) throws -> MCPPayee
    func deletePayee(id: String) throws

    // Scheduled Transactions
    func scheduledTransactions(from: Date?, to: Date?) -> [MCPScheduledTransaction]
    @discardableResult func createScheduledTransaction(value: Double, currencyId: String, type: String, accountId: String, destinationAccountId: String?, dateScheduled: Date, interval: String, isAutomatic: Bool, payeeId: String?, categoryId: String?) throws -> MCPScheduledTransaction
    @discardableResult func updateScheduledTransaction(id: String, value: Double?, currencyId: String?, type: String?, accountId: String?, destinationAccountId: String?, dateScheduled: Date?, interval: String?, isAutomatic: Bool?, payeeId: String?, categoryId: String?) throws -> MCPScheduledTransaction
    func deleteScheduledTransaction(id: String) throws
}

// MARK: - Native format helpers

private let nativeDateFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    f.timeZone = TimeZone(abbreviation: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private let nativeNumFmt: NumberFormatter = {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.maximumFractionDigits = 6
    f.minimumFractionDigits = 2
    return f
}()

private func nativeDate(_ s: String?) -> Date? { s.flatMap { nativeDateFmt.date(from: $0) } }
private func nativeNum(_ s: String?) -> Double { s.flatMap { nativeNumFmt.number(from: $0)?.doubleValue } ?? 0 }
private func fmtDate(_ d: Date) -> String { nativeDateFmt.string(from: d) }
private func fmtNum(_ v: Double) -> String { nativeNumFmt.string(from: NSDecimalNumber(value: v)) ?? "0.00" }

private let noneUUID = "00000000-0000-0000-0000-000000000000"
private func deNone(_ s: String?) -> String { (s == nil || s == noneUUID) ? "" : s! }
private func toNone(_ s: String) -> String? { s.isEmpty ? nil : s }

// Type int ↔ string conversions (matches MoneyCore enum raw values)
private func acctTypeStr(_ v: Int) -> String {
    switch v { case 0: return "cash"; case 1: return "bank"; case 2: return "credit"
               case 4: return "loan"; case 8: return "mortgage"; case 16: return "asset"
               case 32: return "savings"; case 64: return "investment"; default: return "bank" }
}
private func acctTypeInt(_ s: String) -> Int {
    switch s { case "cash": return 0; case "bank": return 1; case "credit": return 2
               case "loan": return 4; case "mortgage": return 8; case "asset": return 16
               case "savings": return 32; case "investment": return 64; default: return 1 }
}
private func txTypeStr(_ v: Int) -> String {
    switch v { case 1: return "income"; case 2: return "expense"; case 4: return "transfer"; default: return "expense" }
}
private func txTypeInt(_ s: String) -> Int {
    switch s { case "income": return 1; case "expense": return 2; case "transfer": return 4; default: return 2 }
}
private func intervalStr(_ v: Int) -> String {
    switch v { case 0: return "never"; case 1: return "daily"; case 2: return "weekly"
               case 4: return "week2"; case 8: return "monthly"; case 16: return "quarterly"
               case 32: return "yearly"; case 64: return "week4"; default: return "never" }
}
private func intervalInt(_ s: String) -> Int {
    switch s { case "never": return 0; case "daily": return 1; case "weekly": return 2
               case "week2": return 4; case "monthly": return 8; case "quarterly": return 16
               case "yearly": return 32; case "week4": return 64; default: return 0 }
}

// MARK: - JSON file-based implementation (native Money app format)

final class JSONDataProvider: DataProvider, @unchecked Sendable {
    private var snapshot: MoneySnapshot
    private let url: URL

    // Cached native dicts keyed by entity ID — preserves fields not modelled here
    private var nativeAccounts:     [String: [String: Any]] = [:]
    private var nativeTransactions: [String: [String: Any]] = [:]
    private var nativeBudgets:      [String: [String: Any]] = [:]
    private var nativeCategories:   [String: [String: Any]] = [:]
    private var nativeCurrencies:   [String: [String: Any]] = [:]
    private var nativePayees:       [String: [String: Any]] = [:]
    private var nativeScheduled:    [String: [String: Any]] = [:]

    // Sections we preserve but don't expose via MCP tools
    private var nativeGroups:       [[String: Any]] = []
    private var nativeConnections:  [[String: Any]] = []
    private var nativeOpen:         [[String: Any]] = []
    private var nativeVersion:      Int = 2

    init(url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPError.internalError("Invalid or missing JSON file at \(url.path)")
        }
        nativeVersion    = (json["version"] as? Int) ?? 2
        nativeGroups     = (json["groups"]      as? [[String: Any]]) ?? []
        nativeConnections = (json["connections"] as? [[String: Any]]) ?? []
        nativeOpen       = (json["open"]        as? [[String: Any]]) ?? []

        func cache(_ key: String, into dict: inout [String: [String: Any]]) {
            for obj in (json[key] as? [[String: Any]]) ?? [] {
                if let id = obj["id"] as? String { dict[id] = obj }
            }
        }
        cache("accounts",     into: &nativeAccounts)
        cache("transactions", into: &nativeTransactions)
        cache("budget",       into: &nativeBudgets)
        cache("categories",   into: &nativeCategories)
        cache("currencies",   into: &nativeCurrencies)
        cache("payees",       into: &nativePayees)
        cache("scheduled",    into: &nativeScheduled)

        snapshot = Self.parse(json)
    }

    // MARK: - Native → in-memory parsing

    private static func parse(_ json: [String: Any]) -> MoneySnapshot {
        let currencies = parseCurrencies(json)
        let accounts   = parseAccounts(json)
        let categories = parseCategories(json)
        let payees     = parsePayees(json)
        let budgets    = parseBudgets(json)
        let transactions = parseTransactions(json, accounts: accounts, payees: payees, categories: categories)
        let scheduled  = parseScheduled(json, accounts: accounts, payees: payees, categories: categories)
        return MoneySnapshot(accounts: accounts, transactions: transactions, budgets: budgets,
                             categories: categories, currencies: currencies, payees: payees,
                             scheduledTransactions: scheduled)
    }

    private static func parseCurrencies(_ json: [String: Any]) -> [MCPCurrency] {
        guard let objs = json["currencies"] as? [[String: Any]] else { return [] }
        return objs.compactMap { obj in
            guard let id        = obj["id"] as? String,
                  let isDefault = obj["default"] as? Bool,
                  let rateStr   = obj["rate"] as? String else { return nil }
            return MCPCurrency(id: id, isDefault: isDefault, exchangeRate: nativeNum(rateStr), accountsCount: 0)
        }
    }

    private static func parseAccounts(_ json: [String: Any]) -> [MCPAccount] {
        guard let objs = json["accounts"] as? [[String: Any]] else { return [] }
        return objs.compactMap { obj in
            guard let id         = obj["id"] as? String,
                  let title      = obj["title"] as? String,
                  let rawType    = obj["type"] as? Int,
                  let balanceStr = obj["balance"] as? String,
                  let currencyId = obj["currency"] as? String, !currencyId.isEmpty else { return nil }
            let isActive  = (obj["active"] as? Bool) ?? true
            let sortOrder = (obj["order"]  as? Int)  ?? 0
            let groupId   = deNone(obj["group"] as? String)
            let startBal  = nativeNum(balanceStr)
            return MCPAccount(id: id, title: title, type: acctTypeStr(rawType),
                              balance: startBal, startBalance: startBal,
                              currencyId: currencyId, groupId: groupId,
                              isActive: isActive, sortOrder: sortOrder, transactionsCount: 0)
        }
    }

    private static func parseCategories(_ json: [String: Any]) -> [MCPCategory] {
        guard let objs = json["categories"] as? [[String: Any]] else { return [] }
        let titleMap = Dictionary(uniqueKeysWithValues: objs.compactMap { obj -> (String, String)? in
            guard let id = obj["id"] as? String, let t = obj["title"] as? String else { return nil }
            return (id, t)
        })
        return objs.compactMap { obj in
            guard let id        = obj["id"] as? String,
                  let title     = obj["title"] as? String,
                  let imageName = obj["image"] as? String else { return nil }
            let parentId    = deNone(obj["parent"] as? String)
            let parentTitle = parentId.isEmpty ? "" : (titleMap[parentId] ?? "")
            return MCPCategory(id: id, title: title, imageName: imageName,
                               parentId: parentId, parentTitle: parentTitle, transactionsCount: 0)
        }
    }

    private static func parsePayees(_ json: [String: Any]) -> [MCPPayee] {
        guard let objs = json["payees"] as? [[String: Any]] else { return [] }
        return objs.compactMap { obj in
            guard let id = obj["id"] as? String, let title = obj["title"] as? String else { return nil }
            return MCPPayee(id: id, title: title, transactionsCount: 0)
        }
    }

    private static func parseBudgets(_ json: [String: Any]) -> [MCPBudget] {
        guard let objs = json["budget"] as? [[String: Any]] else { return [] }
        return objs.compactMap { obj in
            guard let id       = obj["id"] as? String,
                  let rawType  = obj["type"] as? Int,
                  let targetStr = obj["target"] as? String else { return nil }
            let categoryId = deNone(obj["category"] as? String)
            return MCPBudget(id: id, type: txTypeStr(rawType),
                             categoryId: categoryId, categoryTitle: "",
                             categoryImageName: "questionmark",
                             target: nativeNum(targetStr), current: 0, percentage: 0)
        }
    }

    private static func parseTransactions(_ json: [String: Any],
                                          accounts: [MCPAccount],
                                          payees: [MCPPayee],
                                          categories: [MCPCategory]) -> [MCPTransaction] {
        guard let objs = json["transactions"] as? [[String: Any]] else { return [] }
        let acctTitle:  (String) -> String = { id in accounts.first   { $0.id == id }?.title ?? "" }
        let payeeTitle: (String) -> String = { id in payees.first     { $0.id == id }?.title ?? "" }
        let catTitle:   (String) -> String = { id in
            guard let c = categories.first(where: { $0.id == id }) else { return "" }
            return c.parentTitle.isEmpty ? c.title : "\(c.parentTitle): \(c.title)"
        }
        return objs.compactMap { obj in
            guard let id         = obj["id"] as? String,
                  let dateStr    = obj["created"] as? String,
                  let date       = nativeDate(dateStr),
                  let valueStr   = obj["value"] as? String,
                  let rawType    = obj["type"] as? Int,
                  let sourceId   = obj["source"] as? String else { return nil }
            let destId      = deNone(obj["destination"] as? String)
            let payeeId     = deNone(obj["payee"]       as? String)
            let categoryId  = deNone(obj["category"]    as? String)
            let currencyId  = (obj["currency"] as? String) ?? ""
            let exValueStr  = obj["exvalue"] as? String
            let exCurrency  = deNone(obj["excurrency"] as? String)
            return MCPTransaction(
                id: id, dateCreated: date,
                value: nativeNum(valueStr), currencyId: currencyId,
                exchangeValue: nativeNum(exValueStr), exchangeCurrencyId: exCurrency,
                type: txTypeStr(rawType),
                sourceAccountId: sourceId, sourceAccountTitle: acctTitle(sourceId),
                destinationAccountId: destId, destinationAccountTitle: acctTitle(destId),
                payeeId: payeeId, payeeTitle: payeeTitle(payeeId),
                categoryId: categoryId, categoryTitle: catTitle(categoryId),
                notes: (obj["notes"] as? String) ?? ""
            )
        }
    }

    private static func parseScheduled(_ json: [String: Any],
                                       accounts: [MCPAccount],
                                       payees: [MCPPayee],
                                       categories: [MCPCategory]) -> [MCPScheduledTransaction] {
        guard let objs = json["scheduled"] as? [[String: Any]] else { return [] }
        let acctTitle:  (String) -> String = { id in accounts.first   { $0.id == id }?.title ?? "" }
        let payeeTitle: (String) -> String = { id in payees.first     { $0.id == id }?.title ?? "" }
        let catTitle:   (String) -> String = { id in
            guard let c = categories.first(where: { $0.id == id }) else { return "" }
            return c.parentTitle.isEmpty ? c.title : "\(c.parentTitle): \(c.title)"
        }
        return objs.compactMap { obj in
            guard let id        = obj["id"] as? String,
                  let valueStr  = obj["value"] as? String,
                  let rawType   = obj["type"] as? Int,
                  let schedStr  = obj["scheduled"] as? String,
                  let schedDate = nativeDate(schedStr),
                  let rawIntvl  = obj["interval"] as? Int,
                  let accountId = obj["source"] as? String else { return nil }
            let currencyId  = (obj["currency"] as? String) ?? ""
            let destId      = deNone(obj["destination"] as? String)
            let payeeId     = deNone(obj["payee"]       as? String)
            let categoryId  = deNone(obj["category"]    as? String)
            return MCPScheduledTransaction(
                id: id, value: nativeNum(valueStr), currencyId: currencyId,
                type: txTypeStr(rawType), dateScheduled: schedDate,
                interval: intervalStr(rawIntvl),
                isAutomatic: (obj["automatic"] as? Bool) ?? false,
                accountId: accountId, accountTitle: acctTitle(accountId),
                destinationAccountId: destId, destinationAccountTitle: acctTitle(destId),
                payeeTitle: payeeTitle(payeeId), categoryTitle: catTitle(categoryId)
            )
        }
    }

    // MARK: - In-memory → native dict builders

    private func buildNativeAccount(_ a: MCPAccount) -> [String: Any] {
        var obj = nativeAccounts[a.id] ?? [:]
        if obj["created"] == nil { obj["created"] = fmtDate(Date()) }
        obj["id"] = a.id; obj["title"] = a.title
        obj["type"]     = acctTypeInt(a.type)
        obj["balance"]  = fmtNum(a.startBalance)
        obj["currency"] = a.currencyId
        obj["active"]   = a.isActive
        obj["group"]    = a.groupId.isEmpty ? noneUUID : a.groupId
        obj["order"]    = a.sortOrder
        return obj
    }

    private func buildNativeTransaction(_ t: MCPTransaction) -> [String: Any] {
        var obj = nativeTransactions[t.id] ?? [:]
        if obj["created"] == nil { obj["created"] = fmtDate(t.dateCreated) }
        obj["id"]       = t.id
        obj["value"]    = fmtNum(t.value)
        obj["currency"] = t.currencyId
        obj["type"]     = txTypeInt(t.type)
        obj["source"]   = t.sourceAccountId
        obj["notes"]    = t.notes
        if t.exchangeValue != 1.0 || !t.exchangeCurrencyId.isEmpty {
            obj["exvalue"]    = fmtNum(t.exchangeValue)
            obj["excurrency"] = t.exchangeCurrencyId
        }
        if let dest = toNone(t.destinationAccountId) { obj["destination"] = dest }
        else { obj.removeValue(forKey: "destination") }
        if let p = toNone(t.payeeId)    { obj["payee"] = p }    else { obj.removeValue(forKey: "payee") }
        if let c = toNone(t.categoryId) { obj["category"] = c } else { obj.removeValue(forKey: "category") }
        return obj
    }

    private func buildNativeBudget(_ b: MCPBudget) -> [String: Any] {
        var obj = nativeBudgets[b.id] ?? [:]
        if obj["created"] == nil { obj["created"] = fmtDate(Date()) }
        obj["id"]     = b.id
        obj["type"]   = txTypeInt(b.type)
        obj["target"] = fmtNum(b.target)
        if let c = toNone(b.categoryId) { obj["category"] = c } else { obj.removeValue(forKey: "category") }
        return obj
    }

    private func buildNativeCategory(_ c: MCPCategory) -> [String: Any] {
        var obj = nativeCategories[c.id] ?? [:]
        if obj["created"] == nil { obj["created"] = fmtDate(Date()) }
        obj["id"]    = c.id
        obj["title"] = c.title
        obj["image"] = c.imageName
        if let p = toNone(c.parentId) { obj["parent"] = p } else { obj.removeValue(forKey: "parent") }
        return obj
    }

    private func buildNativeCurrency(_ c: MCPCurrency) -> [String: Any] {
        var obj = nativeCurrencies[c.id] ?? [:]
        if obj["created"] == nil { obj["created"] = fmtDate(Date()) }
        obj["id"]      = c.id
        obj["default"] = c.isDefault
        obj["rate"]    = fmtNum(c.exchangeRate)
        return obj
    }

    private func buildNativePayee(_ p: MCPPayee) -> [String: Any] {
        var obj = nativePayees[p.id] ?? [:]
        if obj["created"] == nil { obj["created"] = fmtDate(Date()) }
        obj["id"]    = p.id
        obj["title"] = p.title
        return obj
    }

    private func buildNativeScheduled(_ s: MCPScheduledTransaction) -> [String: Any] {
        var obj = nativeScheduled[s.id] ?? [:]
        if obj["created"] == nil { obj["created"] = fmtDate(Date()) }
        obj["id"]        = s.id
        obj["value"]     = fmtNum(s.value)
        obj["currency"]  = s.currencyId
        obj["type"]      = txTypeInt(s.type)
        obj["scheduled"] = fmtDate(s.dateScheduled)
        obj["interval"]  = intervalInt(s.interval)
        obj["source"]    = s.accountId
        if s.isAutomatic { obj["automatic"] = true } else { obj.removeValue(forKey: "automatic") }
        if let dest = toNone(s.destinationAccountId) { obj["destination"] = dest }
        else { obj.removeValue(forKey: "destination") }
        return obj
    }

    // MARK: - Persistence

    private func save() throws {
        var json: [String: Any] = [:]
        json["version"]      = nativeVersion
        json["accounts"]     = snapshot.accounts.map             { buildNativeAccount($0) }
        json["transactions"] = snapshot.transactions.map         { buildNativeTransaction($0) }
        json["budget"]       = snapshot.budgets.map              { buildNativeBudget($0) }
        json["categories"]   = snapshot.categories.map           { buildNativeCategory($0) }
        json["currencies"]   = snapshot.currencies.map           { buildNativeCurrency($0) }
        json["payees"]       = snapshot.payees.map               { buildNativePayee($0) }
        json["scheduled"]    = snapshot.scheduledTransactions.map{ buildNativeScheduled($0) }
        json["groups"]       = nativeGroups
        json["connections"]  = nativeConnections
        json["open"]         = nativeOpen
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Helpers

    private func newId() -> String { UUID().uuidString.lowercased() }

    private func notFound(_ entity: String, id: String) -> MCPError {
        .invalidParams("\(entity) not found: \(id)")
    }

    private func resolveTitle(accountId: String) -> String {
        snapshot.accounts.first { $0.id == accountId }?.title ?? ""
    }

    private func resolvePayeeTitle(payeeId: String) -> String {
        snapshot.payees.first { $0.id == payeeId }?.title ?? ""
    }

    private func resolveCategoryTitle(categoryId: String) -> String {
        guard let c = snapshot.categories.first(where: { $0.id == categoryId }) else { return "" }
        return c.parentTitle.isEmpty ? c.title : "\(c.parentTitle): \(c.title)"
    }

    private func computedBalance(accountId: String) -> Double {
        let start = snapshot.accounts.first { $0.id == accountId }?.startBalance ?? 0
        return snapshot.transactions.reduce(start) { sum, t in
            switch t.type {
            case "income":   return t.sourceAccountId == accountId ? sum + t.value : sum
            case "expense":  return t.sourceAccountId == accountId ? sum - t.value : sum
            case "transfer":
                if t.sourceAccountId == accountId      { return sum - t.value }
                if t.destinationAccountId == accountId { return sum + t.value }
                return sum
            default: return sum
            }
        }
    }

    private func enrichAccount(_ a: MCPAccount) -> MCPAccount {
        MCPAccount(
            id: a.id, title: a.title, type: a.type,
            balance: computedBalance(accountId: a.id),
            startBalance: a.startBalance,
            currencyId: a.currencyId, groupId: a.groupId,
            isActive: a.isActive, sortOrder: a.sortOrder,
            transactionsCount: snapshot.transactions.filter {
                $0.sourceAccountId == a.id || $0.destinationAccountId == a.id
            }.count
        )
    }

    // MARK: - Account reads

    func accounts(activeOnly: Bool, type: String?) -> [MCPAccount] {
        snapshot.accounts
            .filter { (!activeOnly || $0.isActive) && (type == nil || $0.type == type) }
            .map { enrichAccount($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func account(id: String) -> MCPAccount? {
        snapshot.accounts.first { $0.id == id }.map { enrichAccount($0) }
    }

    // MARK: - Account writes

    func createAccount(title: String, type: String, currencyId: String, startBalance: Double, groupId: String) throws -> MCPAccount {
        let a = MCPAccount(
            id: newId(), title: title, type: type,
            balance: startBalance, startBalance: startBalance,
            currencyId: currencyId, groupId: groupId,
            isActive: true, sortOrder: snapshot.accounts.count, transactionsCount: 0
        )
        snapshot.accounts.append(a)
        try save()
        return enrichAccount(a)
    }

    func updateAccount(id: String, title: String?, type: String?, isActive: Bool?, groupId: String?, sortOrder: Int?, startBalance: Double?) throws -> MCPAccount {
        guard let i = snapshot.accounts.firstIndex(where: { $0.id == id }) else {
            throw notFound("Account", id: id)
        }
        let a = snapshot.accounts[i]
        let sb = startBalance ?? a.startBalance
        let updated = MCPAccount(
            id: a.id, title: title ?? a.title, type: type ?? a.type,
            balance: a.balance, startBalance: sb,
            currencyId: a.currencyId,
            groupId: groupId ?? a.groupId, isActive: isActive ?? a.isActive,
            sortOrder: sortOrder ?? a.sortOrder, transactionsCount: a.transactionsCount
        )
        snapshot.accounts[i] = updated
        try save()
        return enrichAccount(updated)
    }

    func deleteAccount(id: String) throws {
        guard snapshot.accounts.contains(where: { $0.id == id }) else {
            throw notFound("Account", id: id)
        }
        snapshot.accounts.removeAll { $0.id == id }
        nativeAccounts.removeValue(forKey: id)
        try save()
    }

    // MARK: - Transaction reads

    func transactions(accountId: String?, categoryId: String?, payeeId: String?, type: String?, from: Date?, to: Date?, limit: Int?) -> [MCPTransaction] {
        var result = snapshot.transactions
        if let accountId  { result = result.filter { $0.sourceAccountId == accountId || $0.destinationAccountId == accountId } }
        if let categoryId { result = result.filter { $0.categoryId == categoryId } }
        if let payeeId    { result = result.filter { $0.payeeId == payeeId } }
        if let type       { result = result.filter { $0.type == type } }
        if let from       { result = result.filter { $0.dateCreated >= from } }
        if let to         { result = result.filter { $0.dateCreated <= to } }
        result.sort { $0.dateCreated > $1.dateCreated }
        if let limit { result = Array(result.prefix(limit)) }
        return result
    }

    func spendingByCategory(from: Date?, to: Date?) -> [(category: String, total: Double)] {
        let filtered = transactions(accountId: nil, categoryId: nil, payeeId: nil,
                                    type: "expense", from: from, to: to, limit: nil)
        var totals: [String: Double] = [:]
        for t in filtered {
            totals[t.categoryTitle.isEmpty ? "Uncategorized" : t.categoryTitle, default: 0] += t.value
        }
        return totals.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }

    // MARK: - Transaction writes

    func createTransaction(value: Double, currencyId: String, type: String, sourceAccountId: String, destinationAccountId: String?, payeeId: String?, categoryId: String?, notes: String?, dateCreated: Date?) throws -> MCPTransaction {
        let destId = destinationAccountId ?? ""
        let pId    = payeeId    ?? ""
        let cId    = categoryId ?? ""
        let t = MCPTransaction(
            id: newId(), dateCreated: dateCreated ?? Date(),
            value: value, currencyId: currencyId,
            exchangeValue: 1.0, exchangeCurrencyId: "",
            type: type,
            sourceAccountId: sourceAccountId,
            sourceAccountTitle: resolveTitle(accountId: sourceAccountId),
            destinationAccountId: destId,
            destinationAccountTitle: resolveTitle(accountId: destId),
            payeeId: pId, payeeTitle: resolvePayeeTitle(payeeId: pId),
            categoryId: cId, categoryTitle: resolveCategoryTitle(categoryId: cId),
            notes: notes ?? ""
        )
        snapshot.transactions.append(t)
        try save()
        return t
    }

    func updateTransaction(id: String, value: Double?, currencyId: String?, type: String?, sourceAccountId: String?, destinationAccountId: String?, payeeId: String?, categoryId: String?, notes: String?) throws -> MCPTransaction {
        guard let i = snapshot.transactions.firstIndex(where: { $0.id == id }) else {
            throw notFound("Transaction", id: id)
        }
        let old   = snapshot.transactions[i]
        let srcId = sourceAccountId      ?? old.sourceAccountId
        let dstId = destinationAccountId ?? old.destinationAccountId
        let pId   = payeeId              ?? old.payeeId
        let cId   = categoryId           ?? old.categoryId
        let updated = MCPTransaction(
            id: old.id, dateCreated: old.dateCreated,
            value: value ?? old.value, currencyId: currencyId ?? old.currencyId,
            exchangeValue: old.exchangeValue, exchangeCurrencyId: old.exchangeCurrencyId,
            type: type ?? old.type,
            sourceAccountId: srcId, sourceAccountTitle: resolveTitle(accountId: srcId),
            destinationAccountId: dstId, destinationAccountTitle: resolveTitle(accountId: dstId),
            payeeId: pId, payeeTitle: resolvePayeeTitle(payeeId: pId),
            categoryId: cId, categoryTitle: resolveCategoryTitle(categoryId: cId),
            notes: notes ?? old.notes
        )
        snapshot.transactions[i] = updated
        try save()
        return updated
    }

    func deleteTransaction(id: String) throws {
        guard snapshot.transactions.contains(where: { $0.id == id }) else {
            throw notFound("Transaction", id: id)
        }
        snapshot.transactions.removeAll { $0.id == id }
        nativeTransactions.removeValue(forKey: id)
        try save()
    }

    // MARK: - Budget reads

    func budgets() -> [MCPBudget] {
        snapshot.budgets.map { b in
            let catTitle = resolveCategoryTitle(categoryId: b.categoryId)
            let catImage = snapshot.categories.first { $0.id == b.categoryId }?.imageName ?? "questionmark"
            return MCPBudget(id: b.id, type: b.type,
                             categoryId: b.categoryId, categoryTitle: catTitle,
                             categoryImageName: catImage,
                             target: b.target, current: 0, percentage: 0)
        }
    }

    // MARK: - Budget writes

    func createBudget(type: String, categoryId: String, target: Double) throws -> MCPBudget {
        let b = MCPBudget(
            id: newId(), type: type,
            categoryId: categoryId,
            categoryTitle: resolveCategoryTitle(categoryId: categoryId),
            categoryImageName: snapshot.categories.first { $0.id == categoryId }?.imageName ?? "questionmark",
            target: target, current: 0, percentage: 0
        )
        snapshot.budgets.append(b)
        try save()
        return b
    }

    func updateBudget(id: String, type: String?, target: Double?) throws -> MCPBudget {
        guard let i = snapshot.budgets.firstIndex(where: { $0.id == id }) else {
            throw notFound("Budget", id: id)
        }
        let b = snapshot.budgets[i]
        let updated = MCPBudget(
            id: b.id, type: type ?? b.type,
            categoryId: b.categoryId, categoryTitle: b.categoryTitle,
            categoryImageName: b.categoryImageName,
            target: target ?? b.target, current: 0, percentage: 0
        )
        snapshot.budgets[i] = updated
        try save()
        return updated
    }

    func deleteBudget(id: String) throws {
        guard snapshot.budgets.contains(where: { $0.id == id }) else {
            throw notFound("Budget", id: id)
        }
        snapshot.budgets.removeAll { $0.id == id }
        nativeBudgets.removeValue(forKey: id)
        try save()
    }

    // MARK: - Category reads

    func categories() -> [MCPCategory] {
        snapshot.categories.map { c in
            MCPCategory(id: c.id, title: c.title, imageName: c.imageName,
                        parentId: c.parentId, parentTitle: c.parentTitle,
                        transactionsCount: snapshot.transactions.filter { $0.categoryId == c.id }.count)
        }
    }

    // MARK: - Category writes

    func createCategory(title: String, imageName: String?, parentId: String?) throws -> MCPCategory {
        let pId = parentId ?? ""
        let c = MCPCategory(
            id: newId(), title: title,
            imageName: imageName ?? "tag",
            parentId: pId,
            parentTitle: pId.isEmpty ? "" : (snapshot.categories.first { $0.id == pId }?.title ?? ""),
            transactionsCount: 0
        )
        snapshot.categories.append(c)
        try save()
        return c
    }

    func updateCategory(id: String, title: String?, imageName: String?) throws -> MCPCategory {
        guard let i = snapshot.categories.firstIndex(where: { $0.id == id }) else {
            throw notFound("Category", id: id)
        }
        let c = snapshot.categories[i]
        let updated = MCPCategory(
            id: c.id, title: title ?? c.title,
            imageName: imageName ?? c.imageName,
            parentId: c.parentId, parentTitle: c.parentTitle,
            transactionsCount: c.transactionsCount
        )
        snapshot.categories[i] = updated
        try save()
        return updated
    }

    func deleteCategory(id: String) throws {
        guard snapshot.categories.contains(where: { $0.id == id }) else {
            throw notFound("Category", id: id)
        }
        snapshot.categories.removeAll { $0.id == id }
        nativeCategories.removeValue(forKey: id)
        try save()
    }

    // MARK: - Currency reads

    func currencies() -> [MCPCurrency] {
        snapshot.currencies.map { c in
            let count = snapshot.accounts.filter { $0.currencyId == c.id }.count
            return MCPCurrency(id: c.id, isDefault: c.isDefault, exchangeRate: c.exchangeRate, accountsCount: count)
        }
    }

    func defaultCurrency() -> MCPCurrency? { snapshot.currencies.first { $0.isDefault } }

    func exchangeRate(from: String, to: String) -> Double? {
        guard
            let fromRate = snapshot.currencies.first(where: { $0.id == from })?.exchangeRate,
            let toRate   = snapshot.currencies.first(where: { $0.id == to })?.exchangeRate,
            fromRate != 0
        else { return nil }
        return toRate / fromRate
    }

    // MARK: - Currency writes

    func createCurrency(id: String, exchangeRate: Double, isDefault: Bool) throws -> MCPCurrency {
        if snapshot.currencies.contains(where: { $0.id == id }) {
            throw MCPError.invalidParams("Currency already exists: \(id)")
        }
        if isDefault {
            for i in snapshot.currencies.indices where snapshot.currencies[i].isDefault {
                let c = snapshot.currencies[i]
                snapshot.currencies[i] = MCPCurrency(id: c.id, isDefault: false, exchangeRate: c.exchangeRate, accountsCount: c.accountsCount)
            }
        }
        let currency = MCPCurrency(id: id, isDefault: isDefault, exchangeRate: exchangeRate, accountsCount: 0)
        snapshot.currencies.append(currency)
        try save()
        return currency
    }

    func updateCurrency(id: String, exchangeRate: Double?, isDefault: Bool?) throws -> MCPCurrency {
        guard let i = snapshot.currencies.firstIndex(where: { $0.id == id }) else {
            throw notFound("Currency", id: id)
        }
        let c = snapshot.currencies[i]
        let newDefault = isDefault ?? c.isDefault
        if newDefault && !c.isDefault {
            for j in snapshot.currencies.indices where snapshot.currencies[j].isDefault {
                let d = snapshot.currencies[j]
                snapshot.currencies[j] = MCPCurrency(id: d.id, isDefault: false, exchangeRate: d.exchangeRate, accountsCount: d.accountsCount)
            }
        }
        let updated = MCPCurrency(id: c.id, isDefault: newDefault, exchangeRate: exchangeRate ?? c.exchangeRate, accountsCount: c.accountsCount)
        snapshot.currencies[i] = updated
        try save()
        return updated
    }

    func deleteCurrency(id: String) throws {
        guard snapshot.currencies.contains(where: { $0.id == id }) else {
            throw notFound("Currency", id: id)
        }
        snapshot.currencies.removeAll { $0.id == id }
        nativeCurrencies.removeValue(forKey: id)
        try save()
    }

    // MARK: - Payee reads

    func payees(query: String?) -> [MCPPayee] {
        var result = snapshot.payees.map { p in
            MCPPayee(id: p.id, title: p.title,
                     transactionsCount: snapshot.transactions.filter { $0.payeeId == p.id }.count)
        }
        if let q = query?.lowercased(), !q.isEmpty {
            result = result.filter { $0.title.lowercased().contains(q) }
        }
        return result.sorted { $0.title < $1.title }
    }

    // MARK: - Payee writes

    func createPayee(title: String) throws -> MCPPayee {
        let p = MCPPayee(id: newId(), title: title, transactionsCount: 0)
        snapshot.payees.append(p)
        try save()
        return p
    }

    func updatePayee(id: String, title: String) throws -> MCPPayee {
        guard let i = snapshot.payees.firstIndex(where: { $0.id == id }) else {
            throw notFound("Payee", id: id)
        }
        let p = snapshot.payees[i]
        let updated = MCPPayee(id: p.id, title: title, transactionsCount: p.transactionsCount)
        snapshot.payees[i] = updated
        try save()
        return updated
    }

    func deletePayee(id: String) throws {
        guard snapshot.payees.contains(where: { $0.id == id }) else {
            throw notFound("Payee", id: id)
        }
        snapshot.payees.removeAll { $0.id == id }
        nativePayees.removeValue(forKey: id)
        try save()
    }

    // MARK: - Scheduled Transaction reads

    func scheduledTransactions(from: Date?, to: Date?) -> [MCPScheduledTransaction] {
        var result = snapshot.scheduledTransactions
        if let from { result = result.filter { $0.dateScheduled >= from } }
        if let to   { result = result.filter { $0.dateScheduled <= to } }
        return result.sorted { $0.dateScheduled < $1.dateScheduled }
    }

    // MARK: - Scheduled Transaction writes

    func createScheduledTransaction(value: Double, currencyId: String, type: String, accountId: String, destinationAccountId: String?, dateScheduled: Date, interval: String, isAutomatic: Bool, payeeId: String?, categoryId: String?) throws -> MCPScheduledTransaction {
        let destId = destinationAccountId ?? ""
        let pId    = payeeId    ?? ""
        let cId    = categoryId ?? ""
        let s = MCPScheduledTransaction(
            id: newId(), value: value, currencyId: currencyId, type: type,
            dateScheduled: dateScheduled, interval: interval, isAutomatic: isAutomatic,
            accountId: accountId, accountTitle: resolveTitle(accountId: accountId),
            destinationAccountId: destId, destinationAccountTitle: resolveTitle(accountId: destId),
            payeeTitle: resolvePayeeTitle(payeeId: pId), categoryTitle: resolveCategoryTitle(categoryId: cId)
        )
        // Pre-populate native cache so payee/category IDs are preserved on save
        var obj: [String: Any] = ["id": s.id, "created": fmtDate(Date())]
        if !pId.isEmpty { obj["payee"] = pId }
        if !cId.isEmpty { obj["category"] = cId }
        nativeScheduled[s.id] = obj
        snapshot.scheduledTransactions.append(s)
        try save()
        return s
    }

    func updateScheduledTransaction(id: String, value: Double?, currencyId: String?, type: String?, accountId: String?, destinationAccountId: String?, dateScheduled: Date?, interval: String?, isAutomatic: Bool?, payeeId: String?, categoryId: String?) throws -> MCPScheduledTransaction {
        guard let i = snapshot.scheduledTransactions.firstIndex(where: { $0.id == id }) else {
            throw notFound("ScheduledTransaction", id: id)
        }
        let old    = snapshot.scheduledTransactions[i]
        let accId  = accountId            ?? old.accountId
        let destId = destinationAccountId ?? old.destinationAccountId
        // Update payee/category IDs in the native cache if supplied
        if let pId = payeeId {
            if pId.isEmpty { nativeScheduled[id]?.removeValue(forKey: "payee") }
            else { nativeScheduled[id, default: [:]]["payee"] = pId }
        }
        if let cId = categoryId {
            if cId.isEmpty { nativeScheduled[id]?.removeValue(forKey: "category") }
            else { nativeScheduled[id, default: [:]]["category"] = cId }
        }
        let resolvedPayeeTitle = payeeId != nil
            ? resolvePayeeTitle(payeeId: payeeId ?? "")
            : old.payeeTitle
        let resolvedCatTitle = categoryId != nil
            ? resolveCategoryTitle(categoryId: categoryId ?? "")
            : old.categoryTitle
        let updated = MCPScheduledTransaction(
            id: old.id, value: value ?? old.value, currencyId: currencyId ?? old.currencyId,
            type: type ?? old.type,
            dateScheduled: dateScheduled ?? old.dateScheduled,
            interval: interval ?? old.interval,
            isAutomatic: isAutomatic ?? old.isAutomatic,
            accountId: accId, accountTitle: resolveTitle(accountId: accId),
            destinationAccountId: destId, destinationAccountTitle: resolveTitle(accountId: destId),
            payeeTitle: resolvedPayeeTitle, categoryTitle: resolvedCatTitle
        )
        snapshot.scheduledTransactions[i] = updated
        try save()
        return updated
    }

    func deleteScheduledTransaction(id: String) throws {
        guard snapshot.scheduledTransactions.contains(where: { $0.id == id }) else {
            throw notFound("ScheduledTransaction", id: id)
        }
        snapshot.scheduledTransactions.removeAll { $0.id == id }
        nativeScheduled.removeValue(forKey: id)
        try save()
    }
}

// MARK: - JSON encoding helper (for tool responses)

func prettyJSON<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else { return "{}" }
    return string
}
