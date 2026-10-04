import Foundation
import Testing
@testable import HomeworkKit

/// 工程定义的唯一来源是 macos/project.yml：Info.plist / entitlements 都由 xcodegen 从它生成。
/// 这些用例守住「不许再出现第二份手写 plist」——曾经 build-app.sh 里有一份手抄副本，
/// 两边一旦漂移，Xcode 里跑得好好的、发出去的 DMG 却会缺权限描述。
private func macosRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HomeworkKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // macos
}

private func spec() throws -> String {
    try String(contentsOf: macosRoot().appendingPathComponent("project.yml"), encoding: .utf8)
}

@Test func buildScriptHasNoHandWrittenInfoPlist() throws {
    let script = try String(
        contentsOf: macosRoot().appendingPathComponent("scripts/build-app.sh"),
        encoding: .utf8
    )
    #expect(!script.contains("cat > \"$APP/Contents/Info.plist\""), "Info.plist 只能由 project.yml 生成")
    #expect(!script.contains("CFBundleShortVersionString"), "版本号应走 MARKETING_VERSION 交给 xcodebuild")
    #expect(script.contains("xcodebuild"), "构建应走唯一的 xcodebuild 路径")
    #expect(script.contains("CODE_SIGNING_ALLOWED=NO"), "签名应由脚本按 SIGN_IDENTITY 完成")
}

@Test func specCarriesKeysThatShippedBuildsNeed() throws {
    let yml = try spec()
    for key in [
        "CFBundleDisplayName", "CFBundleIconFile", "LSMinimumSystemVersion",
        "NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription",
        "NSHighResolutionCapable", "LSApplicationCategoryType",
    ] {
        #expect(yml.contains(key), "project.yml 缺少 \(key)：发布产物会缺这一项")
    }
    #expect(yml.contains("com.apple.security.app-sandbox"))
    #expect(yml.contains("Support/HomeworkMac.entitlements"))
}

@Test func generatedArtifactsAreNotTracked() throws {
    let ignore = try String(
        contentsOf: macosRoot().deletingLastPathComponent().appendingPathComponent(".gitignore"),
        encoding: .utf8
    )
    #expect(ignore.contains("macos/HomeworkMac.xcodeproj/"))
    #expect(ignore.contains("macos/Support/"))
}

@Test func specKeepsUniversalFriendlySettings() throws {
    let yml = try spec()
    #expect(yml.contains("macOS: \"26.0\""))
    #expect(yml.contains("local.zyh.homework"))
    #expect(yml.contains("path: Sources/HomeworkMac"))
    #expect(yml.contains("product: HomeworkKit"))
}

/// 脚本必须带可执行位：git 只记录 100644/100755，丢了的话
/// 别人克隆 features/Mac 后会 Permission denied（本地 chmod 挡不住下一次提交）。
@Test func scriptsKeepExecutableBit() throws {
    let script = macosRoot().appendingPathComponent("scripts/build-app.sh")
    let attrs = try FileManager.default.attributesOfItem(atPath: script.path)
    let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
    #expect(mode & 0o111 != 0, "build-app.sh 需要可执行位（chmod +x 并 git update-index --chmod=+x）")

    let dmg = macosRoot().appendingPathComponent("scripts/make-dmg.sh")
    let dmgMode = (try FileManager.default.attributesOfItem(atPath: dmg.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
    #expect(dmgMode & 0o111 != 0, "make-dmg.sh 需要可执行位")
}
