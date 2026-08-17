import XCTest
@testable import MoneyMCPServer

final class DataProviderTests: XCTestCase {
    // MARK: - Helpers

    private func makeProvider() throws -> (JSONDataProvider, URL) {
        let src = Bundle.module.url(forResource: "sample", withExtension: "json")!
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.copyItem(at: src, to: dst)
        addTeardownBlock { try? FileManager.default.removeItem(at: dst) }
        return try (JSONDataProvider(url: dst), dst)
    }

    // MARK: - Currencies

    func testParseCurrencies() throws {
        let (provider, _) = try makeProvider()
        let currencies = provider.currencies()
        XCTAssertEqual(currencies.count, 2)
        let gbp = try XCTUnwrap(currencies.first { $0.id == "GBP" })
        XCTAssertTrue(gbp.isDefault)
        XCTAssertEqual(gbp.exchangeRate, 1.0, accuracy: 0.001)
        let usd = try XCTUnwrap(currencies.first { $0.id == "USD" })
        XCTAssertFalse(usd.isDefault)
        XCTAssertEqual(usd.exchangeRate, 1.25, accuracy: 0.001)
    }

    func testDefaultCurrency() throws {
        let (provider, _) = try makeProvider()
        XCTAssertEqual(try XCTUnwrap(provider.defaultCurrency()).id, "GBP")
    }

    func testCurrencyAccountsCount() throws {
        let (provider, _) = try makeProvider()
        let gbp = try XCTUnwrap(provider.currencies().first { $0.id == "GBP" })
        XCTAssertEqual(gbp.accountsCount, 2)
    }

    func testExchangeRate() throws {
        let (provider, _) = try makeProvider()
        let rate = try XCTUnwrap(provider.exchangeRate(from: "GBP", to: "USD"))
        XCTAssertEqual(rate, 1.25, accuracy: 0.001)
    }

    // MARK: - Accounts

    func testParseAccounts() throws {
        let (provider, _) = try makeProvider()
        let accounts = provider.accounts(activeOnly: false, type: nil)
        XCTAssertEqual(accounts.count, 2)
        let checking = try XCTUnwrap(accounts.first { $0.id == "acct-checking" })
        XCTAssertEqual(checking.title, "Checking")
        XCTAssertEqual(checking.type, "bank")
        XCTAssertEqual(checking.startBalance, 1000.0, accuracy: 0.001)
        XCTAssertEqual(checking.currencyId, "GBP")
        XCTAssertTrue(checking.isActive)
        XCTAssertEqual(checking.sortOrder, 0)
        XCTAssertEqual(checking.groupId, "") // noneUUID mapped to ""
    }

    func testAccountTypeStrings() throws {
        // Checking=bank(1), Savings=savings(32) — verifies int→string conversion
        let (provider, _) = try makeProvider()
        let accounts = provider.accounts(activeOnly: false, type: nil)
        XCTAssertEqual(accounts.first { $0.id == "acct-checking" }?.type, "bank")
        XCTAssertEqual(accounts.first { $0.id == "acct-savings" }?.type, "savings")
    }

    func testFilterAccountsByType() throws {
        let (provider, _) = try makeProvider()
        XCTAssertEqual(provider.accounts(activeOnly: false, type: "bank").count, 1)
        XCTAssertEqual(provider.accounts(activeOnly: false, type: "savings").count, 1)
        XCTAssertEqual(provider.accounts(activeOnly: false, type: "cash").count, 0)
    }

    func testAccountTransactionsCount() throws {
        let (provider, _) = try makeProvider()
        // Checking is source for all 3 transactions
        let checking = try XCTUnwrap(provider.account(id: "acct-checking"))
        XCTAssertEqual(checking.transactionsCount, 3)
        // Savings is destination for the transfer only
        let savings = try XCTUnwrap(provider.account(id: "acct-savings"))
        XCTAssertEqual(savings.transactionsCount, 1)
    }

    // MARK: - Balance computation

    func testComputedBalance_income() throws {
        // Checking: start=1000 + 3000 income - 45.50 expense - 200 transfer = 3754.50
        let (provider, _) = try makeProvider()
        let checking = try XCTUnwrap(provider.account(id: "acct-checking"))
        XCTAssertEqual(checking.balance, 3754.50, accuracy: 0.001)
    }

    func testComputedBalance_transferDestination() throws {
        // Savings: start=500 + 200 transfer in = 700
        let (provider, _) = try makeProvider()
        let savings = try XCTUnwrap(provider.account(id: "acct-savings"))
        XCTAssertEqual(savings.balance, 700.0, accuracy: 0.001)
    }

    func testStartBalanceNotAffectedByTransactions() throws {
        let (provider, _) = try makeProvider()
        let checking = try XCTUnwrap(provider.account(id: "acct-checking"))
        XCTAssertEqual(checking.startBalance, 1000.0, accuracy: 0.001)
    }

    // MARK: - Transactions

    func testParseTransactionCount() throws {
        let (provider, _) = try makeProvider()
        let txns = provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        XCTAssertEqual(txns.count, 3)
    }

    func testTransactionTypeStrings() throws {
        let (provider, _) = try makeProvider()
        let all = provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        XCTAssertTrue(all.contains { $0.type == "income" })
        XCTAssertTrue(all.contains { $0.type == "expense" })
        XCTAssertTrue(all.contains { $0.type == "transfer" })
    }

    func testIncomeTitleDenormalization() throws {
        let (provider, _) = try makeProvider()
        let income = try XCTUnwrap(provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: "income",
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        ).first)
        XCTAssertEqual(income.id, "tx-income")
        XCTAssertEqual(income.value, 3000.0, accuracy: 0.001)
        XCTAssertEqual(income.sourceAccountTitle, "Checking")
        XCTAssertEqual(income.categoryTitle, "Salary")
        XCTAssertEqual(income.notes, "January salary")
    }

    func testExpenseSubcategoryTitle() throws {
        // Category "Groceries" has parent "Food" — title should be "Food: Groceries"
        let (provider, _) = try makeProvider()
        let expense = try XCTUnwrap(provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: "expense",
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        ).first)
        XCTAssertEqual(expense.payeeTitle, "Tesco")
        XCTAssertEqual(expense.categoryTitle, "Food: Groceries")
    }

    func testTransferTitles() throws {
        let (provider, _) = try makeProvider()
        let transfer = try XCTUnwrap(provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: "transfer",
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        ).first)
        XCTAssertEqual(transfer.sourceAccountTitle, "Checking")
        XCTAssertEqual(transfer.destinationAccountTitle, "Savings")
        XCTAssertEqual(transfer.destinationAccountId, "acct-savings")
    }

    func testTransactionsSortedNewestFirst() throws {
        let (provider, _) = try makeProvider()
        let txns = provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        let dates = txns.map { $0.dateCreated }
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testFilterTransactionsByAccount() throws {
        let (provider, _) = try makeProvider()
        // Savings is only involved in the transfer
        let txns = provider.transactions(
            accountId: "acct-savings",
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.id, "tx-transfer")
    }

    func testFilterTransactionsByCategory() throws {
        let (provider, _) = try makeProvider()
        let txns = provider.transactions(
            accountId: nil,
            categoryId: "cat-salary",
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.id, "tx-income")
    }

    func testFilterTransactionsByPayee() throws {
        let (provider, _) = try makeProvider()
        let txns = provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: "payee-tesco",
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.id, "tx-expense")
    }

    func testFilterTransactionsLimit() throws {
        let (provider, _) = try makeProvider()
        let txns = provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: 2
        )
        XCTAssertEqual(txns.count, 2)
    }

    // MARK: - Categories

    func testParseCategories() throws {
        let (provider, _) = try makeProvider()
        XCTAssertEqual(provider.categories().count, 3)
    }

    func testSubcategoryParentTitle() throws {
        let (provider, _) = try makeProvider()
        let groceries = try XCTUnwrap(provider.categories().first { $0.id == "cat-groceries" })
        XCTAssertEqual(groceries.parentId, "cat-food")
        XCTAssertEqual(groceries.parentTitle, "Food")
    }

    func testRootCategoryHasEmptyParent() throws {
        let (provider, _) = try makeProvider()
        let food = try XCTUnwrap(provider.categories().first { $0.id == "cat-food" })
        XCTAssertEqual(food.parentId, "")
        XCTAssertEqual(food.parentTitle, "")
    }

    func testCategoryTransactionsCount() throws {
        let (provider, _) = try makeProvider()
        let salary = try XCTUnwrap(provider.categories().first { $0.id == "cat-salary" })
        XCTAssertEqual(salary.transactionsCount, 1)
        let groceries = try XCTUnwrap(provider.categories().first { $0.id == "cat-groceries" })
        XCTAssertEqual(groceries.transactionsCount, 1)
    }

    // MARK: - Payees

    func testParsePayees() throws {
        let (provider, _) = try makeProvider()
        let payees = provider.payees(query: nil)
        XCTAssertEqual(payees.count, 1)
        XCTAssertEqual(payees.first?.title, "Tesco")
    }

    func testPayeeTransactionsCount() throws {
        let (provider, _) = try makeProvider()
        let tesco = try XCTUnwrap(provider.payees(query: nil).first { $0.id == "payee-tesco" })
        XCTAssertEqual(tesco.transactionsCount, 1)
    }

    func testPayeeSearch() throws {
        let (provider, _) = try makeProvider()
        XCTAssertEqual(provider.payees(query: "tes").count, 1)
        XCTAssertEqual(provider.payees(query: "TES").count, 1) // case-insensitive
        XCTAssertEqual(provider.payees(query: "xyz").count, 0)
    }

    // MARK: - Budgets

    func testParseBudgets() throws {
        let (provider, _) = try makeProvider()
        let budgets = provider.budgets()
        XCTAssertEqual(budgets.count, 1)
        let b = try XCTUnwrap(budgets.first)
        XCTAssertEqual(b.type, "expense")
        XCTAssertEqual(b.categoryId, "cat-groceries")
        XCTAssertEqual(b.categoryTitle, "Food: Groceries")
        XCTAssertEqual(b.target, 200.0, accuracy: 0.001)
    }

    // MARK: - Scheduled transactions

    func testParseScheduledTransactions() throws {
        let (provider, _) = try makeProvider()
        let scheduled = provider.scheduledTransactions(from: nil, to: nil)
        XCTAssertEqual(scheduled.count, 1)
        let s = try XCTUnwrap(scheduled.first)
        XCTAssertEqual(s.id, "sched-1")
        XCTAssertEqual(s.value, 3000.0, accuracy: 0.001)
        XCTAssertEqual(s.type, "income")
        XCTAssertEqual(s.interval, "monthly")
        XCTAssertTrue(s.isAutomatic)
        XCTAssertEqual(s.accountTitle, "Checking")
        XCTAssertEqual(s.categoryTitle, "Salary")
    }

    // MARK: - Spending by category

    func testSpendingByCategory() throws {
        let (provider, _) = try makeProvider()
        let spending = provider.spendingByCategory(from: nil, to: nil)
        XCTAssertEqual(spending.count, 1)
        XCTAssertEqual(spending.first?.category, "Food: Groceries")
        XCTAssertEqual(try XCTUnwrap(spending.first).total, 45.50, accuracy: 0.001)
    }

    // MARK: - CRUD: Accounts

    func testCreateAccount() throws {
        let (provider, url) = try makeProvider()
        let acct = try provider.createAccount(
            title: "Cash Wallet",
            type: "cash",
            currencyId: "GBP",
            startBalance: 50.0,
            groupId: ""
        )
        XCTAssertFalse(acct.id.isEmpty)
        XCTAssertEqual(acct.type, "cash")
        // Persisted correctly
        let reloaded = try JSONDataProvider(url: url)
        XCTAssertNotNil(reloaded.account(id: acct.id))
        XCTAssertEqual(reloaded.account(id: acct.id)?.type, "cash")
    }

    func testUpdateAccount() throws {
        let (provider, url) = try makeProvider()
        let updated = try provider.updateAccount(
            id: "acct-checking",
            title: "Main Checking",
            type: nil,
            isActive: nil,
            groupId: nil,
            sortOrder: nil,
            startBalance: nil
        )
        XCTAssertEqual(updated.title, "Main Checking")
        XCTAssertEqual(updated.startBalance, 1000.0, accuracy: 0.001) // unchanged
        XCTAssertEqual(try JSONDataProvider(url: url).account(id: "acct-checking")?.title, "Main Checking")
    }

    func testDeleteAccount() throws {
        let (provider, url) = try makeProvider()
        try provider.deleteAccount(id: "acct-savings")
        XCTAssertNil(provider.account(id: "acct-savings"))
        XCTAssertNil(try JSONDataProvider(url: url).account(id: "acct-savings"))
    }

    func testUpdateAccountNotFound() throws {
        let (provider, _) = try makeProvider()
        XCTAssertThrowsError(try provider.updateAccount(
            id: "no-such-account",
            title: nil,
            type: nil,
            isActive: nil,
            groupId: nil,
            sortOrder: nil,
            startBalance: nil
        ))
    }

    // MARK: - CRUD: Transactions

    func testCreateTransaction() throws {
        let (provider, url) = try makeProvider()
        let tx = try provider.createTransaction(
            value: 12.99,
            currencyId: "GBP",
            type: "expense",
            sourceAccountId: "acct-checking",
            destinationAccountId: nil,
            payeeId: "payee-tesco",
            categoryId: "cat-groceries",
            notes: "Lunch",
            dateCreated: nil,
            reconciled: false
        )
        XCTAssertEqual(tx.value, 12.99, accuracy: 0.001)
        XCTAssertEqual(tx.payeeTitle, "Tesco")
        XCTAssertEqual(tx.categoryTitle, "Food: Groceries")
        XCTAssertEqual(tx.sourceAccountTitle, "Checking")
        XCTAssertFalse(tx.isReconciled)
        let reloaded = try JSONDataProvider(url: url)
        let reloadedTxns = reloaded.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        XCTAssertTrue(reloadedTxns.contains { $0.id == tx.id })
    }

    func testCreateTransactionReconciled() throws {
        let (provider, url) = try makeProvider()
        let tx = try provider.createTransaction(
            value: 12.99,
            currencyId: "GBP",
            type: "expense",
            sourceAccountId: "acct-checking",
            destinationAccountId: nil,
            payeeId: "payee-tesco",
            categoryId: "cat-groceries",
            notes: "Lunch",
            dateCreated: nil,
            reconciled: true
        )
        XCTAssertTrue(tx.isReconciled)
        let reloaded = try JSONDataProvider(url: url)
        let reloadedTx = try XCTUnwrap(reloaded.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        ).first { $0.id == tx.id })
        XCTAssertTrue(reloadedTx.isReconciled)
    }

    func testUpdateTransactionReconciled() throws {
        let (provider, _) = try makeProvider()
        let updated = try provider.updateTransaction(
            id: "tx-income",
            value: nil,
            currencyId: nil,
            type: nil,
            sourceAccountId: nil,
            destinationAccountId: nil,
            payeeId: nil,
            categoryId: nil,
            notes: nil,
            reconciled: true
        )
        XCTAssertTrue(updated.isReconciled)
    }

    func testFilterTransactionsByReconciled() throws {
        let (provider, _) = try makeProvider()
        _ = try provider.setReconciled(ids: ["tx-income"], reconciled: true)
        let reconciled = provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: true,
            limit: nil
        )
        XCTAssertEqual(reconciled.map(\.id), ["tx-income"])
        let unreconciled = provider.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: false,
            limit: nil
        )
        XCTAssertEqual(Set(unreconciled.map(\.id)), ["tx-expense", "tx-transfer"])
    }

    func testSetReconciledBulk() throws {
        let (provider, url) = try makeProvider()
        let updated = try provider.setReconciled(ids: ["tx-income", "tx-expense"], reconciled: true)
        XCTAssertEqual(updated.count, 2)
        XCTAssertTrue(updated.allSatisfy(\.isReconciled))
        let reloaded = try JSONDataProvider(url: url)
        let reloadedTxns = reloaded.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: true,
            limit: nil
        )
        XCTAssertEqual(Set(reloadedTxns.map(\.id)), ["tx-income", "tx-expense"])
    }

    func testSetReconciledNotFoundThrows() throws {
        let (provider, _) = try makeProvider()
        XCTAssertThrowsError(try provider.setReconciled(ids: ["nonexistent"], reconciled: true))
    }

    func testDeleteTransaction() throws {
        let (provider, url) = try makeProvider()
        try provider.deleteTransaction(id: "tx-income")
        let reloaded = try JSONDataProvider(url: url)
        let reloadedTxns = reloaded.transactions(
            accountId: nil,
            categoryId: nil,
            payeeId: nil,
            type: nil,
            from: nil,
            to: nil,
            reconciled: nil,
            limit: nil
        )
        XCTAssertFalse(reloadedTxns.contains { $0.id == "tx-income" })
    }

    func testDeleteTransactionNotFound() throws {
        let (provider, _) = try makeProvider()
        XCTAssertThrowsError(try provider.deleteTransaction(id: "nonexistent"))
    }

    // MARK: - CRUD: Payees

    func testCreatePayee() throws {
        let (provider, url) = try makeProvider()
        let payee = try provider.createPayee(title: "Sainsbury's")
        XCTAssertFalse(payee.id.isEmpty)
        XCTAssertNotNil(try JSONDataProvider(url: url).payees(query: nil).first { $0.id == payee.id })
    }

    func testUpdatePayee() throws {
        let (provider, url) = try makeProvider()
        let updated = try provider.updatePayee(id: "payee-tesco", title: "Tesco Express")
        XCTAssertEqual(updated.title, "Tesco Express")
        XCTAssertEqual(try JSONDataProvider(url: url).payees(query: nil)
            .first { $0.id == "payee-tesco" }?.title, "Tesco Express")
    }

    func testDeletePayee() throws {
        let (provider, url) = try makeProvider()
        try provider.deletePayee(id: "payee-tesco")
        XCTAssertNil(try JSONDataProvider(url: url).payees(query: nil).first { $0.id == "payee-tesco" })
    }

    // MARK: - CRUD: Currencies

    func testCreateCurrencyDuplicateThrows() throws {
        let (provider, _) = try makeProvider()
        XCTAssertThrowsError(try provider.createCurrency(id: "GBP", exchangeRate: 1.0, isDefault: false))
    }

    func testCreateCurrencyAsDefaultDemotesExisting() throws {
        let (provider, _) = try makeProvider()
        _ = try provider.createCurrency(id: "EUR", exchangeRate: 1.18, isDefault: true)
        XCTAssertFalse(provider.currencies().first { $0.id == "GBP" }?.isDefault ?? true)
        XCTAssertTrue(provider.currencies().first { $0.id == "EUR" }?.isDefault ?? false)
    }

    // MARK: - CRUD: Categories

    func testCreateCategory() throws {
        let (provider, url) = try makeProvider()
        let cat = try provider.createCategory(title: "Transport", imageName: "car", parentId: nil)
        XCTAssertEqual(cat.parentId, "")
        XCTAssertNotNil(try JSONDataProvider(url: url).categories().first { $0.id == cat.id })
    }

    func testCreateSubcategory() throws {
        let (provider, _) = try makeProvider()
        let sub = try provider.createCategory(title: "Supermarket", imageName: nil, parentId: "cat-food")
        XCTAssertEqual(sub.parentId, "cat-food")
        XCTAssertEqual(sub.parentTitle, "Food")
    }

    // MARK: - CRUD: Scheduled Transactions

    func testCreateScheduledTransaction() throws {
        let (provider, url) = try makeProvider()
        let date = Date(timeIntervalSince1970: 1_740_000_000)
        let s = try provider.createScheduledTransaction(
            value: 800.0,
            currencyId: "GBP",
            type: "expense",
            accountId: "acct-checking",
            destinationAccountId: nil,
            dateScheduled: date,
            interval: "monthly",
            isAutomatic: false,
            payeeId: "payee-tesco",
            categoryId: "cat-groceries"
        )
        XCTAssertEqual(s.value, 800.0, accuracy: 0.001)
        XCTAssertEqual(s.interval, "monthly")
        XCTAssertEqual(s.payeeTitle, "Tesco")
        XCTAssertEqual(s.categoryTitle, "Food: Groceries")
        // Payee/category IDs persisted via native cache
        let reloaded = try JSONDataProvider(url: url)
        XCTAssertTrue(reloaded.scheduledTransactions(from: nil, to: nil).contains { $0.id == s.id })
    }

    // MARK: - Round-trip fidelity

    func testRoundTripPreservesGroups() throws {
        let (provider, url) = try makeProvider()
        _ = try provider.createPayee(title: "Test")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let groups = json["groups"] as? [[String: Any]]
        XCTAssertEqual(groups?.count, 1)
        XCTAssertEqual(groups?.first?["title"] as? String, "Accounts")
    }

    func testRoundTripPreservesDateCreated() throws {
        let (provider, url) = try makeProvider()
        _ = try provider.updateAccount(
            id: "acct-checking",
            title: "Updated",
            type: nil,
            isActive: nil,
            groupId: nil,
            sortOrder: nil,
            startBalance: nil
        )
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let accounts = try XCTUnwrap(json["accounts"] as? [[String: Any]])
        let checking = try XCTUnwrap(accounts.first { $0["id"] as? String == "acct-checking" })
        XCTAssertEqual(checking["created"] as? String, "2025-01-01T10:00:00Z")
    }

    func testRoundTripPreservesVersion() throws {
        let (provider, url) = try makeProvider()
        _ = try provider.createPayee(title: "Test")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
    }

    func testRoundTripAccountTypeInt() throws {
        // Create cash account, reload, verify type survived int→string→int round-trip
        let (provider, url) = try makeProvider()
        let acct = try provider.createAccount(
            title: "Wallet",
            type: "cash",
            currencyId: "GBP",
            startBalance: 0.0,
            groupId: ""
        )
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let accounts = try XCTUnwrap(json["accounts"] as? [[String: Any]])
        let wallet = try XCTUnwrap(accounts.first { $0["id"] as? String == acct.id })
        XCTAssertEqual(wallet["type"] as? Int, 0) // cash = 0
    }

    // MARK: - Error cases

    func testInvalidJSONThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try Data("not valid json".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try JSONDataProvider(url: url))
    }
}
