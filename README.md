# BGM Manager

YouTubeをブラウザで開かずに、メニューバーからぱっとBGMを流すためのmacOSアプリです。
動画は表示せず、`mpv`で音声だけを再生します。

コンセプトはミニマル、省メモリです。
Chromeのタブを開きっぱなしにせず、作業中のBGMだけを軽く流せることを目的にしています。

## 必要なもの

```sh
brew install jq mpv yt-dlp
```

## macOSアプリ

ビルド:

```sh
./macos/BGMManager/build.sh
```

生成された`dist/BGM Manager.app`を`/Applications`へコピーして起動します。

### 使い方

1. YouTube URLをコピーします。
2. メニューバーの`♫`をクリックします。
3. `URLを追加...`を選びます。
4. クリップボードにURLがあれば入力欄へ自動で入ります。
5. `追加`を押すと曲リストに保存されます。
6. `曲を選ぶ`から曲を選ぶと再生します。

再生中は`♫ 12:34 / 1:00:00`のように、タイマーの経過時間と設定時間を表示します。
メニュー内では、曲位置、タイマー残り、一時停止、停止を操作できます。

一時停止は同じ曲の同じ位置から戻る操作です。
停止は再生を終了して、現在位置も捨てる操作です。

曲リストは`data/bgm-list.json`です。このファイルは個人用URLを含むためGit管理外です。
初回起動時に自動作成されます。サンプルは`data/bgm-list.example.json`です。

## CLI

```sh
./scripts/bgm-manager.sh manage
./scripts/bgm-manager.sh play
./scripts/bgm-manager.sh play 1 1h
./scripts/bgm-manager.sh play --url 'https://www.youtube.com/watch?v=...' --time 30m
```
