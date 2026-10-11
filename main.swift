import ApplicationServices
import CoreGraphics
import Foundation
import ServiceManagement

// ── 設定 ─────────────────────────────────────────────
// 既定値はここで決める。利用者は次のように上書きできる（Scroll Fixer の再起動後に反映）:
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
let linesPerNotch = setting("linesPerNotch", default: 10, range: 1...100)
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
    print("scroll-fixer 起動中（1ノッチ = \(linesPerNotch) 行）。停止は Ctrl+C。")
    return true
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

CFRunLoopRun()
