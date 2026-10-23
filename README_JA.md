<div align="center">

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_TR.md">Türkçe</a> ·
  <strong>日本語</strong> ·
  <a href="README_ZH.md">简体中文</a> ·
  <a href="README_ES.md">Español</a>
</p>

<img src="assets/icon.png" width="128" height="128" alt="EXdl アイコン">

# EXdl
### macOS向け 外付けドライブ インストール＆管理マネージャー

**Macアプリを外付けドライブに直接インストールし、LaunchpadやSpotlightでもそのまま利用可能にします。**

<br>

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white)](#システム要件)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF?style=flat-square)](#システム要件)
[![Release](https://img.shields.io/badge/Release-v1.1.1-blue?style=flat-square)](https://github.com/erdembeler/exdl/releases/latest)
[![Notarized](https://img.shields.io/badge/Apple-notarized-34C759?style=flat-square)](#インストール方法)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white)](Package.swift)
[![MIT License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

[**最新リリースをダウンロード**](https://github.com/erdembeler/exdl/releases/latest) &nbsp;·&nbsp; [仕組み](#仕組み) &nbsp;·&nbsp; [必要な権限](#必要な権限とその理由) &nbsp;·&nbsp; [ソースからのビルド](#ソースからのビルド)

</div>

<br>

EXdlは、外付けSSDをmacOSの自然なアプリケーション保存先として活用できるように設計された、軽量なネイティブメニューバーアプリケーションです。

---

## 開発の背景と課題

Macの内蔵SSDは購入後に増設や換装ができません。開発ツール、3Dグラフィックソフト、ゲームエンジン、大型ゲームなどをインストールすると、内蔵ストレージはあっという間に逼迫します。

通常、ダウンロードした `.dmg` ファイルを開くと、内蔵ディスクの `/Applications` へドラッグ＆ドロップするよう案内されます。これを手動で外付けSSDに移動し、エイリアスやシンボリックリンクを作成した場合、以下の問題が生じます：
- macOSのLaunchpad、Spotlight、Sequoiaの「アプリケーション」一覧がシンボリックリンクを正しく認識せず、検索や一覧に表示されない。
- 外付けドライブを取り外しているときに起動すると、エラーも出ずに無言で起動失敗するか、予期しないシステムエラーが発生する。
- アプリの自動アップデートが実行されると、アップデーターがリンクを上書きして内蔵ディスクにフルサイズの実体を書き戻してしまい、知らない間に内蔵ストレージが消費される。

---

## 仕組み

<p align="center">
  <img src="assets/how-it-works.svg" width="720" alt="EXdlのインストールとスマートランチャーの動作フロー">
</p>

EXdlは壊れやすい従来のシンボリックリンクを使いません。代わりに**スマートアプリスタブ（Smart App Stub）**方式を採用しています：
1. `.dmg` ファイルを開くと、EXdlが自動検知し、外付けドライブを直接保存先とするインストール画面を表示します。
2. アプリケーション本体は外付けドライブに安全にコピーされます。
3. 内蔵の `/Applications` フォルダには、元アプリのアイコン・メタデータ・Bundle IDを保持した約500KBの軽量なランチャーが配置されます。
4. Launchpad、Spotlight、Dockは、これを完全なネイティブアプリケーションとして認識・インデックスします。
5. 外付けドライブが未接続の状態で起動した場合でも、安全にドライブの接続を促す案内ダイアログを表示します。

---

## 主な機能

- **ディスクイメージ自動検知** — `.dmg` のマウントを検知して外付けドライブへの導入を案内し、完了後は自動でイメージをアンマウントします。
- **アップデート保護** — アプリ内アップデーターによって内蔵ディスクへ上書きされた場合、それを検知して自動で外付けドライブへ再退避します。
- **ストレージ管理ダッシュボード** — 内蔵・外付けドライブの容量とアプリ一覧を一元管理。既存の内蔵アプリをワンクリックで外付けへ移行、または復元できます。
- **非対応アプリの保護** — 起動ディスク外への移動で不具合が発生するアプリ（Xcode、開発ツールチェーン、Apple純正システムアプリ、System Extensionsや常駐ログイン項目を持つツール）を自動判定し、内蔵ディスクに保護します。
- **10種のカスタムメニューバーアイコン** — 設定から10種類のRetinaベクターテンプレートアイコンを選択可能（初期値: EXモノグラム）。監視稼働時は塗りつぶし（Solid）、一時停止時はアウトライン（Hollow）で視認性を保ちます。
- **ネイティブOTAアップデート** — GitHub Releasesを通じて新バージョンを検知し、署名検証を行った上で自動アップデートと再起動を行います。
- **軽量かつ高いプライバシー** — バックグラウンドで静かに常駐し、アップデート確認以外の外部通信は一切行いません。

---

## 比較表

| 項目 | 標準のmacOS | 手動シンボリックリンク | EXdlを使用 |
| :-- | :-- | :-- | :-- |
| **DMGインストール先** | 内蔵ディスクのみ | 手動コピーが必要 | 外付けドライブへ直接ワンクリック導入 |
| **Launchpad / Spotlight** | 対応 | インデックスされないことが多い | 完全対応（通常アプリと同等） |
| **ドライブ未接続時** | 該当なし | エラーなしで終了または不具合 | ドライブ接続を促す通知を表示 |
| **アプリの自動更新** | 内蔵ディスクに保持 | リンクが破壊される | 外付けドライブへの配置を自動復元 |
| **内蔵SSDの容量節約** | なし (0 GB) | 節約できるが不安定 | 確実かつ安定した容量節約 |

---

## 必要な権限とその理由

EXdlが正常に動作するために、macOSの以下のプライバシー権限が必要です：

1. **アプリ管理 (`App Management`) — 必須**
   - **理由:** `/Applications` 内に軽量なランチャースタブを作成し、外付けドライブとの間でアプリケーションを安全に移動するために必要です。
   - **設定方法:** *システム設定 → プライバシーとセキュリティ → アプリ管理* でEXdlをオンにします。一覧に表示されない場合は左下の `+` ボタンから `/Applications/EXdl.app` を追加してください。
2. **フルディスクアクセス (`Full Disk Access`) — 推奨**
   - **理由:** 「ダウンロード」フォルダ内のディスクイメージの読み取りや外付けドライブへの書き込み時に、macOSの確認ダイアログが重複して表示されるのを防ぎます。
   - **設定方法:** *システム設定 → プライバシーとセキュリティ → フルディスクアクセス* でEXdlをオンにします。

---

## インストール方法

1. [GitHub Releases](https://github.com/erdembeler/exdl/releases/latest) ページから最新版（`EXdl-1.1.1.dmg` または `EXdl-1.1.1.zip`）をダウンロードします。
2. ダウンロードしたディスクイメージを開き、**EXdl** を **Applications** フォルダへドラッグします。
3. EXdlを起動します。初期設定アシスタントに従い、言語設定、保存先ドライブ、権限の付与を行います。
4. 設定完了後、EXdlはメニューバーに常駐します。

配布されるすべてのバイナリはApple Developer IDでコード署名され、Appleによる公証（Notarization）を受けています。

---

## システム要件

- macOS 14 Sonoma 以降
- Apple Silicon Mac (M1 / M2 / M3 / M4)
- **APFS**（推奨）または **Mac OS 拡張（ジャーナリング）** でフォーマットされた外付けストレージ

---

## ソースからのビルド

```bash
git clone https://github.com/erdembeler/exdl.git
cd exdl

# アプリケーションバンドルをビルド
./build_app.sh

# DMGおよびZIP配布パッケージを作成
./package_release.sh
```

---

## ライセンス

本プロジェクトは [MIT License](LICENSE) のもとで公開されています。
