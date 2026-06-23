# mac-scroll-fixer

Mac のホイールスクロールの加速を無効化し、1ノッチあたりのスクロール量を固定値にする常駐ツール。
トラックパッド / Magic Mouse の連続スクロールには影響しません。

アクセシビリティ権限が必要ですが、`.app` バンドルとして「Scroll Fixer」という独立したアプリ名で
権限一覧に表示されます（Terminal 経由ではありません）。

## ビルド

```sh
./build.sh
```

`main.swift` をコンパイルし、ad-hoc 署名済みの `ScrollFixer.app` を生成します。

## 実行

```sh
open ScrollFixer.app
```

初回はイベントタップの作成に失敗します。
「システム設定 → プライバシーとセキュリティ → アクセシビリティ」で **Scroll Fixer** に権限を付与し、
再度起動してください。

> **注意（ad-hoc 署名）:** `build.sh` の署名はビルドごとに変わるため、
> 再ビルドするとアクセシビリティ権限を付与し直す必要があります。
> （再ビルドしても権限を保持したい場合は、自己署名証明書または Developer ID での署名が必要です。）

## 終了

```sh
killall scroll-fixer
```

## 設定

[main.swift](main.swift) 冒頭の `linesPerNotch` で 1 ノッチあたりの行数を変更できます（既定: 6）。
変更後は `./build.sh` で再ビルドしてください。

## ログイン時に自動起動する場合

1. ビルドした `ScrollFixer.app` を `/Applications` にコピーします:

   ```sh
   cp -R ScrollFixer.app /Applications/
   ```

2. 同梱の LaunchAgent を登録します:

   ```sh
   cp local.scroll-fixer.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/local.scroll-fixer.plist
   ```

## 自動起動をやめる場合

```sh
launchctl unload ~/Library/LaunchAgents/local.scroll-fixer.plist
```

[local.scroll-fixer.plist](local.scroll-fixer.plist) は
`/Applications/ScrollFixer.app/Contents/MacOS/scroll-fixer` を起動します。
別の場所に置く場合はパスを書き換えてください。
この場合も **Scroll Fixer** にアクセシビリティ権限を付与してください。
