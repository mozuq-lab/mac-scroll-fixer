import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ServiceManagement

// ── 設定 ─────────────────────────────────────────────
// 既定値はここで決める。linesPerNotch はメニューバーから変えられる（すぐに反映して保存する）。
// どちらのキーも次のように上書きできる（Scroll Fixer の再起動後に反映）:
//   defaults write com.mozuq-lab.ScrollFixer linesPerNotch -int 6
func setting(_ key: String, default value: Int64, range: ClosedRange<Int64>) -> Int64 {
    guard UserDefaults.standard.object(forKey: key) != nil else { return value }
    let stored = Int64(UserDefaults.standard.integer(forKey: key))
    guard range.contains(stored) else {
        NSLog("%@", "\(key) = \(stored) は範囲外（\(range.lowerBound)〜\(range.upperBound)）のため、既定値 \(value) を使います。")
        return value
    }
    return stored
}

// 1ノッチあたりのスクロール行数
let linesPerNotchKey = "linesPerNotch"
let defaultLinesPerNotch: Int64 = 10
var linesPerNotch = setting(linesPerNotchKey, default: defaultLinesPerNotch, range: 1...100)
// 1行あたりのピクセル数（macOS の標準的な換算は 10px/行）
let pixelsPerLine = setting("pixelsPerLine", default: 10, range: 1...100)
// ─────────────────────────────────────────────────────

var eventTap: CFMachPort?

// 指定軸の加速されたデルタを固定値に置き換える（符号＝向きは維持）。
// 行単位・固定小数点・ピクセル単位の 3 フィールドを一貫した値に揃える。
// アプリによって参照するフィールドが異なるため、ゼロにすると
// ピクセル系を読むアプリ（Chrome 等）でスクロールが効かなくなる。
func flattenDelta(_ event: CGEvent,
                  delta: CGEventField,
                  fixedPt: CGEventField,
                  point: CGEventField) {
    let value = event.getIntegerValueField(delta)
    guard value != 0 else { return }
    let sign: Int64 = value > 0 ? 1 : -1
    event.setIntegerValueField(delta, value: sign * linesPerNotch)
    event.setDoubleValueField(fixedPt, value: Double(sign * linesPerNotch))
    event.setIntegerValueField(point, value: sign * linesPerNotch * pixelsPerLine)
}

func scrollCallback(proxy: CGEventTapProxy,
                    type: CGEventType,
                    event: CGEvent,
                    refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {

    // タップがタイムアウト等で無効化されたら再有効化する
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

    // トラックパッド / Magic Mouse（連続・ピクセル単位）はそのまま通す
    if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
        return Unmanaged.passUnretained(event)
    }

    // 縦方向
    flattenDelta(event,
                 delta: .scrollWheelEventDeltaAxis1,
                 fixedPt: .scrollWheelEventFixedPtDeltaAxis1,
                 point: .scrollWheelEventPointDeltaAxis1)

    // 横方向
    flattenDelta(event,
                 delta: .scrollWheelEventDeltaAxis2,
                 fixedPt: .scrollWheelEventFixedPtDeltaAxis2,
                 point: .scrollWheelEventPointDeltaAxis2)

    return Unmanaged.passUnretained(event)
}

// アクセシビリティ権限があればイベントタップを作って有効にする。権限がなければ false を返す
func installEventTap() -> Bool {
    guard AXIsProcessTrusted() else { return false }

    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                      place: .headInsertEventTap,
                                      options: .defaultTap,
                                      eventsOfInterest: mask,
                                      callback: scrollCallback,
                                      userInfo: nil) else {
        return false
    }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        NSLog("RunLoop ソースの作成に失敗しました。")
        exit(1)
    }
    eventTap = tap
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    print("scroll-fixer 起動中（1ノッチ = \(linesPerNotch) 行）。停止は Ctrl+C かメニューバーの「終了」。")
    return true
}

// ── メニューバー ─────────────────────────────────────
// メニューから選べるスクロール量（行）。defaults でほかの値にしていれば、それも並べる
let linesPerNotchChoices: [Int64] = [1, 2, 3, 4, 5, 6, 8, 10, 15, 20]

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    // 権限がないときだけ表示する項目
    var permissionItems: [NSMenuItem] = []
    var linesItems: [NSMenuItem] = []

    // 項目は起動時に一度だけ作る。メニューを開いている最中に作り直すと、
    // VoiceOver などが参照している項目が消えて押せなくなるため
    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse",
                                           accessibilityDescription: "Scroll Fixer")
        let menu = NSMenu()
        menu.delegate = self

        let noPermission = menu.addItem(withTitle: "アクセシビリティ権限がありません",
                                        action: nil, keyEquivalent: "")
        let openSettings = menu.addItem(withTitle: "「システム設定」を開く…",
                                        action: #selector(openAccessibilitySettings), keyEquivalent: "")
        openSettings.target = self
        let separator = NSMenuItem.separator()
        menu.addItem(separator)
        permissionItems = [noPermission, openSettings, separator]

        menu.addItem(withTitle: "1 ノッチのスクロール量", action: nil, keyEquivalent: "")
        for lines in Set(linesPerNotchChoices + [linesPerNotch]).sorted() {
            let title = lines == defaultLinesPerNotch ? "\(lines) 行（既定）" : "\(lines) 行"
            let item = menu.addItem(withTitle: title,
                                    action: #selector(selectLinesPerNotch(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(lines)
            item.indentationLevel = 1
            linesItems.append(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Scroll Fixer を終了",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // メニューを開くたびに、いまの設定と権限の状態を映す
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in permissionItems { item.isHidden = eventTap != nil }
        for item in linesItems { item.state = Int64(item.tag) == linesPerNotch ? .on : .off }
    }

    // 選んだ値は次のスクロールから効き、次回の起動にも引き継ぐ
    @objc func selectLinesPerNotch(_ sender: NSMenuItem) {
        linesPerNotch = Int64(sender.tag)
        UserDefaults.standard.set(sender.tag, forKey: linesPerNotchKey)
    }

    @objc func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// 初回の起動時に、ログイン項目に登録する（macOS が「ログイン項目が追加されました」と通知する）。
// 利用者が「システム設定」でオフにした後は、登録し直さない。
// ビルドしたフォルダから起動した場合など、アプリケーションフォルダ以外では登録しない。
func registerLoginItemOnFirstLaunch() {
    let key = "didRegisterLoginItem"
    let path = Bundle.main.bundlePath
    let applicationFolders = ["/Applications/", NSHomeDirectory() + "/Applications/"]
    guard !UserDefaults.standard.bool(forKey: key),
          applicationFolders.contains(where: { path.hasPrefix($0) }) else { return }
    do {
        try SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    } catch {
        NSLog("%@", "ログイン項目に登録できませんでした: \(error.localizedDescription)")
    }
}

let app = NSApplication.shared
// Info.plist の LSUIElement と同じく Dock に出さない（.app にせず実行ファイルを直接起動した場合のため）
app.setActivationPolicy(.accessory)
let menuController = MainActor.assumeIsolated { MenuController() }

registerLoginItemOnFirstLaunch()

if !installEventTap() {
    // 権限がなければ、システムの許可ダイアログ（「システム設定」を開くボタン付き）を出す
    let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    NSLog("アクセシビリティ権限を待っています。「システム設定」>「プライバシーとセキュリティ」>「アクセシビリティ」で Scroll Fixer をオンにしてください。")

    // 許可されたら、起動し直さなくても動き出すよう 1 秒ごとに確かめる
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
        if installEventTap() { timer.invalidate() }
    }
}

app.run()
