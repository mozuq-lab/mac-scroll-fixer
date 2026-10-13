# mac-scroll-fixer

Mac のホイールスクロールの加速を無効化し、1ノッチあたりのスクロール量を固定値にする常駐ツール。
トラックパッド / Magic Mouse の連続スクロールには影響しません。

アクセシビリティ権限が必要ですが、`.app` バンドルとして「Scroll Fixer」という独立したアプリ名で
権限一覧に表示されます（Terminal 経由ではありません）。

## 動作要件

- macOS 13 (Ventura) 以降
- Apple シリコン / Intel のどちらの Mac でも動きます

## インストールと起動

1. `ScrollFixer.app` を「アプリケーション」フォルダに入れて、ダブルクリックで起動します。
2. 初回はアクセシビリティ権限を求めるダイアログが出ます。「システム設定を開く」を選び、
   「プライバシーとセキュリティ」>「アクセシビリティ」で **Scroll Fixer** をオンにします。
   オンにすると、起動し直さなくても数秒以内に効き始めます。

起動するとメニューバーにマウスのアイコンが出ます（Dock には出ません）。

### ログイン時の自動起動

「アプリケーション」フォルダから初めて起動したときに、Scroll Fixer は自分をログイン項目に登録します
（macOS が「ログイン項目が追加されました」と通知します）。

自動起動が不要な場合は、「システム設定」>「一般」>「ログイン項目と機能拡張」（macOS 13/14 では「ログイン項目」）で Scroll Fixer をオフにしてください。
一度オフにすると、Scroll Fixer が登録し直すことはありません。

ビルドしたフォルダなど、「アプリケーション」フォルダ以外から起動した場合は登録しません。

## 終了

メニューバーのアイコンから「Scroll Fixer を終了」を選びます。
ターミナルからは `killall scroll-fixer` で終了できます。

## 設定

1 ノッチあたりのスクロール量は、メニューバーのアイコンから選べます（1〜20 行）。
選んだ値はすぐに効き、次回の起動にも引き継がれます。

メニューにない値にしたい場合や、`pixelsPerLine` を変えたい場合は、`defaults` コマンドを使います。
変更後は Scroll Fixer を起動し直してください。

```sh
defaults write com.mozuq-lab.ScrollFixer linesPerNotch -int 7   # 1 ノッチあたりの行数（既定: 10）
killall scroll-fixer; open -a ScrollFixer
```

| キー | 内容 | 既定 | 範囲 |
| --- | --- | --- | --- |
| `linesPerNotch` | 1 ノッチあたりのスクロール行数 | 10 | 1〜100 |
| `pixelsPerLine` | 1 行あたりのピクセル数（ピクセル単位でスクロールするアプリ向け） | 10 | 1〜100 |

既定に戻すには `defaults delete com.mozuq-lab.ScrollFixer linesPerNotch` を実行します。

## ビルド

```sh
./build.sh
```

`main.swift` をコンパイルし、署名済みの `ScrollFixer.app` を生成します。
Apple シリコンと Intel の両方で動くユニバーサル版になります。
対応する macOS は `Info.plist` の `LSMinimumSystemVersion` に合わせます。

署名には、キーチェーンにある証明書を次の順に探して使います。

| 順 | 証明書 | 用途 |
| --- | --- | --- |
| 1 | 環境変数 `SIGN_IDENTITY` で指定したもの | 証明書の名前の一部か SHA-1 ハッシュで指定する。`-` なら ad-hoc 署名 |
| 2 | Developer ID Application | 他の Mac に配る場合。公証にはこれが必要（有料の Apple Developer Program） |
| 3 | Apple Development | 自分の Mac だけで使う場合（無料の Apple ID で作れる） |
| 4 | なし（ad-hoc 署名） | 証明書がない場合 |

> **注意（ad-hoc 署名）:** ad-hoc 署名はビルドごとに変わるため、
> 再ビルドするとアクセシビリティ権限を付与し直す必要があります。
> 証明書で署名していれば、再ビルドしても権限は保持されます。

## 他の Mac に配る（公証）

他の Mac で開くには、Developer ID Application 証明書で署名し、Apple の公証を受ける必要があります。

最初に 1 回だけ、公証用の認証情報をキーチェーンに保存します。パスワードは入力欄で聞かれるので、
appleid.apple.com で作った **App 用パスワード** を入力します。

```sh
xcrun notarytool store-credentials meetrec-notary --apple-id <Apple ID> --team-id <チーム ID>
```

その後は、次のコマンドでビルドから公証までをまとめて実行できます（数分かかります）。

```sh
./build.sh --notarize
```

署名、公証の申請、公証結果の埋め込み（stapler）、Gatekeeper での確認を順に行い、
配布用の `ScrollFixer.zip` を作ります。
キーチェーンプロファイルの名前が `meetrec-notary` 以外の場合は、`NOTARY_PROFILE` 環境変数で指定します。
