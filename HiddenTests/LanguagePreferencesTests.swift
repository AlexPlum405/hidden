//
//  LanguagePreferencesTests.swift
//  HiddenTests
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import XCTest
import AppKit
@testable import Hidden_Bar

/// Contract: the App language row offers every localization the build ships,
/// stores the choice as CFBundle's AppleLanguages key, and Simplified Chinese
/// stays a complete translation of the English strings.
final class LanguagePreferencesTests: XCTestCase {

    private var suiteName = ""
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        // The suite AppDefaults.domain(of:) maps a test store to.
        suiteName = AppDefaults.testSuiteName
        store = UserDefaults(suiteName: suiteName)
        store.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // Given the localizations this build ships
    // When the Language popup lists them
    // Then Simplified Chinese is there under its own name and Base is not
    func test_shippedLanguagesUseNativeNames() {
        let languages = LanguagePreferences.languages()
        XCTAssertTrue(languages.contains { $0.code == "zh-Hans" })
        XCTAssertFalse(languages.contains { $0.code == "Base" })
        XCTAssertEqual(languages.first { $0.code == "zh-Hans" }?.name, "简体中文")
    }

    // Given no choice yet
    // When a language is picked, then System is picked
    // Then the app's own domain holds the code, then not even an empty list
    func test_overrideIsTheAppleLanguagesKey() {
        XCTAssertNil(LanguagePreferences.override(in: store))
        LanguagePreferences.setOverride("zh-Hans", in: store)
        let written = store.persistentDomain(forName: suiteName)?[LanguagePreferences.appleLanguagesKey] as? [String]
        XCTAssertEqual(written, ["zh-Hans"])
        XCTAssertEqual(LanguagePreferences.override(in: store), "zh-Hans")
        LanguagePreferences.setOverride(nil, in: store)
        XCTAssertNil(store.persistentDomain(forName: suiteName)?[LanguagePreferences.appleLanguagesKey])
        XCTAssertNil(LanguagePreferences.override(in: store))
    }

    // Given macOS keeps the system language in the global domain
    // When the row reads the app's own domain
    // Then an absent key means "follow the system", not the global value a
    // plain lookup would return
    func test_overrideReadsTheAppsDomainOnly() {
        XCTAssertNil(store.persistentDomain(forName: suiteName)?[LanguagePreferences.appleLanguagesKey])
        XCTAssertNil(LanguagePreferences.override(in: store))
        // A plain lookup does see the global domain, which is why the row cannot
        // use one.
        XCTAssertNotNil(store.stringArray(forKey: LanguagePreferences.appleLanguagesKey))
    }

    // Given a stored code
    // When the build still ships it
    // Then it wins; a code the build dropped falls back to a language it does ship
    func test_effectiveKeepsOnlyShippedCodes() {
        LanguagePreferences.setOverride("zh-Hans", in: store)
        XCTAssertEqual(LanguagePreferences.effective(in: .main, store: store), "zh-Hans")
        LanguagePreferences.setOverride("xx-Unknown", in: store)
        let effective = LanguagePreferences.effective(in: .main, store: store)
        XCTAssertNotEqual(effective, "xx-Unknown")
        XCTAssertTrue(Bundle.main.localizations.contains(effective))
    }

    // Given every English string
    // When looking at Simplified Chinese
    // Then each one is translated with the same format placeholders
    func test_simplifiedChineseCoversEverything() throws {
        let english = try strings(for: "en")
        let chinese = try strings(for: "zh-Hans")
        let missing = Set(english.keys).subtracting(chinese.keys)
        XCTAssertTrue(missing.isEmpty, "zh-Hans is missing \(missing.sorted())")
        for (key, value) in english {
            XCTAssertEqual(chinese[key]?.components(separatedBy: "%@").count,
                           value.components(separatedBy: "%@").count, key)
            XCTAssertEqual(chinese[key]?.components(separatedBy: "%d").count,
                           value.components(separatedBy: "%d").count, key)
        }
        XCTAssertEqual(chinese["Language"], "语言")
    }

    // Given the built app
    // When Restart Now builds its helper
    // Then the helper waits for this process to exit before opening the bundle,
    // rather than opening on a fixed delay and racing the old instance
    func test_relaunchHelperWaitsForThisProcess() {
        let url = URL(fileURLWithPath: "/Applications/Hidden Bar.app")
        let arguments = AppRelaunch.arguments(for: url, pid: 4321)
        XCTAssertEqual(arguments.first, "-c")
        let script = arguments[1]
        XCTAssertTrue(script.contains("kill -0"))
        XCTAssertTrue(script.contains("/bin/sleep 0.2"))
        XCTAssertFalse(script.contains("sleep 1;"))
        XCTAssertTrue(script.contains("/usr/bin/open"))
        XCTAssertEqual(arguments[2], "sh")
        XCTAssertEqual(arguments[3], "4321")
        XCTAssertEqual(arguments[4], url.path)
    }

    // Given the build this test runs in
    // When Restart Now reports whether it can work
    // Then it is offered in the direct build only, as the App Store build is
    // sandboxed and cannot run the wait
    func test_relaunchFollowsTheBuild() {
        XCTAssertEqual(AppRelaunch.isAvailable, SettingsBuild.current == .direct)
    }

    // Given the General pane
    // When it lays out
    // Then the language popup lists System first and writes the picked language
    func test_generalPaneWritesThePickedLanguage() throws {
        LanguagePreferences.setOverride(nil)
        let controller = PreferencesWindowController(context: .live)
        defer { controller.window?.close() }
        let general = try XCTUnwrap(controller.pane(.general) as? PreferencesViewController)
        _ = general.view
        let popup = try XCTUnwrap(Self.view(with: PreferencesViewController.languagePopupIdentifier, in: general.view) as? NSPopUpButton)
        XCTAssertEqual(popup.item(at: 0)?.title, "System (follow macOS)".localized)
        XCTAssertTrue(popup.itemTitles.contains("简体中文"))

        let index = try XCTUnwrap(popup.itemTitles.firstIndex(of: "简体中文"))
        popup.selectItem(at: index)
        _ = NSApp.sendAction(try XCTUnwrap(popup.action), to: popup.target, from: popup)
        XCTAssertEqual(LanguagePreferences.override(), "zh-Hans")
        LanguagePreferences.setOverride(nil)
    }

    private func strings(for localization: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                  inDirectory: nil, forLocalization: localization))
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    private static func view(with identifier: NSUserInterfaceItemIdentifier, in root: NSView) -> NSView? {
        if root.identifier == identifier { return root }
        for child in root.subviews {
            if let match = view(with: identifier, in: child) { return match }
        }
        return nil
    }
}
