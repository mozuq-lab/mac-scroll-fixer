# mac-scroll-fixer

Mac のホイールスクロールの加速を無効化し、1ノッチあたりのスクロール量を固定値にする常駐ツール。
トラックパッド / Magic Mouse の連続スクロールには影響しません。

## ビルド

```sh
swiftc main.swift -o scroll-fixer
```

## 実行

```sh
./scroll-fixer
```

初回はイベントタップの作成に失敗するので、
「システム設定 → プライバシーとセキュリティ → アクセシビリティ」で
実行元（Terminal など）に権限を付与してから再実行してください。

## 設定

[main.swift](main.swift) 冒頭の `linesPerNotch` で 1 ノッチあたりの行数を変更できます（既定: 3）。
変更後は再ビルドしてください。

## ログイン時に自動起動する場合

launchd の LaunchAgent として登録します（例）:

```sh
cat > ~/Library/LaunchAgents/local.scroll-fixer.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.scroll-fixer</string>
    <key>ProgramArguments</key>
    <array><string>/usr/local/bin/scroll-fixer</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/local.scroll-fixer.plist
```

この場合はバイナリ（`/usr/local/bin/scroll-fixer`）自体にアクセシビリティ権限を付与してください。
