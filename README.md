# BGM Manager

YouTubeの音声を`mpv`で再生する、macOS用の作業BGMメニューバーアプリです。

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
メニューバーの`♫`から曲、再生時間、一時停止、停止を操作できます。

曲リストは`data/bgm-list.json`です。編集後はメニューの「曲リストを再読み込み」を選びます。

## CLI

```sh
./scripts/bgm-manager.sh manage
./scripts/bgm-manager.sh play
./scripts/bgm-manager.sh play 1 1h
./scripts/bgm-manager.sh play --url 'https://www.youtube.com/watch?v=...' --time 30m
```

