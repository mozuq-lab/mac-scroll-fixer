import Foundation
import CoreGraphics

// ── 設定 ─────────────────────────────────────────────
// 1ノッチあたりのスクロール行数。好みに合わせて変えてください。
let linesPerNotch: Int64 = 3
// 1行あたりのピクセル数（macOS の標準的な換算は 10px/行）
let pixelsPerLine: Int64 = 10
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

let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                  place: .headInsertEventTap,
                                  options: .defaultTap,
                                  eventsOfInterest: mask,
                                  callback: scrollCallback,
                                  userInfo: nil) else {
    FileHandle.standardError.write(
        "イベントタップの作成に失敗しました。アクセシビリティ権限を付与して再実行してください。\n"
            .data(using: .utf8)!)
    exit(1)
}

eventTap = tap
guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
    FileHandle.standardError.write("RunLoop ソースの作成に失敗しました。\n".data(using: .utf8)!)
    exit(1)
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("scroll-fixer 起動中（1ノッチ = \(linesPerNotch) 行）。停止は Ctrl+C。")
CFRunLoopRun()
