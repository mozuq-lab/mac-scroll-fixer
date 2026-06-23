#!/bin/sh
# main.swift をビルドし、ad-hoc 署名済みの ScrollFixer.app を生成する。
set -e

APP="ScrollFixer.app"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# 実行ファイルを Contents/MacOS/ に出力（名前は Info.plist の CFBundleExecutable と一致させる）
swiftc -O main.swift -o "$APP/Contents/MacOS/scroll-fixer"

# Info.plist を配置
cp Info.plist "$APP/Contents/Info.plist"

# バンドルを ad-hoc 署名（"-" が ad-hoc 署名）。
# これでアクセシビリティ一覧に "Scroll Fixer" として単独表示される。
# 注意: ad-hoc 署名は再ビルドのたびに署名が変わるため、
#       その都度アクセシビリティ権限の付与し直しが必要。
codesign --force --sign - "$APP"

echo "ビルド完了: $DIR/$APP"
