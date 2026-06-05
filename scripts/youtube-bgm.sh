#!/bin/bash

# ytp-dlpが入っているか確認
if ! command -v yt-dlp &> /dev/null; then
    echo "yt-dlp が見つかりません。brew install yt-dlp ffmpeg mpv でインストールしてください。"
    exit 1
fi

echo "YouTube URL (または動画ID) を入力してください:"
read url

echo "ストリーミング再生を開始します... (Ctrl+C で停止)"
# --no-part: ダウンロードを完了させずストリーミングに徹する
# -f "ba[abr<128]": 128kbps以下の低音質（BGMに十分）を選択して通信量を節約
# mpv --cache=yes: 途切れないように少しだけキャッシュする
yt-dlp -f "ba[abr<128]/ba" -o - "$url" | mpv --cache=yes --no-video -
