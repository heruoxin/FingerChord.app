// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing

@testable import FingerChord

@Suite(.serialized)
struct ReleaseTests {
    @Test func translationsHaveMatchingKeysAndFormatSpecifiers() throws {
        func strings(_ code: String) throws -> [String: String] {
            let path = try #require(L10n.resources.path(forResource: code, ofType: "lproj"))
            let data = try Data(
                contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings"))
            return try #require(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try strings("en")
        let specifier = try NSRegularExpression(pattern: "%[@ld]+")
        func formats(_ value: String) -> [String] {
            specifier.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) }
        }
        for code in ["zh-Hans", "zh-Hant"] {
            let translation = try strings(code)
            #expect(Set(english.keys) == Set(translation.keys))
            for (key, value) in english {
                #expect(formats(value) == formats(translation[key] ?? ""))
                #expect(translation[key]?.isEmpty == false)
            }
        }
    }

    @Test @MainActor func languageChangesResolveWithoutRestarting() {
        let previous = L10n.language
        defer { L10n.language = previous }
        for (language, name) in [
            (AppLanguage.english, "FingerChord"), (.simplifiedChinese, "指间"), (.traditionalChinese, "指間"),
        ] {
            L10n.language = language
            #expect(L10n.text("app.name") == name)
            #expect(L10n.text("preview.contacts", 5).contains("5"))
        }
    }

    @Test @MainActor func previewModelAndUnstartedMonitorRelease() {
        weak var model: AppModel?
        weak var monitor: InputMonitor?
        autoreleasepool {
            let instance = AppModel(monitorsInput: false)
            model = instance
            monitor = instance.monitor
        }
        #expect(model == nil)
        #expect(monitor == nil)
    }
}
