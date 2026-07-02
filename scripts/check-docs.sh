#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
APP="$ROOT_DIR/macos/BGMManager/App.m"

check_pair() {
    local description="$1"
    local readme_pattern="$2"
    local app_pattern="$3"

    if ! grep -Fq -- "$readme_pattern" "$README"; then
        echo "README missing: $description ($readme_pattern)" >&2
        return 1
    fi
    if ! grep -Fq -- "$app_pattern" "$APP"; then
        echo "App missing: $description ($app_pattern)" >&2
        return 1
    fi
}

check_pair "URL add flow" "Add URL..." "Add URL"
check_pair "song submenu" '`Songs`' 'menuItemWithTitle:@"Songs"'
check_pair "song management submenu" '`Edit Songs`' 'menuItemWithTitle:@"Edit Songs"'
check_pair "song rename" '`Rename...`' 'initWithTitle:@"Rename..."'
check_pair "song delete" '`Delete...`' 'initWithTitle:@"Delete..."'
check_pair "three-hour default" "デフォルトでは、3時間タイマー" "self.duration = 10800"
check_pair "compact progress display" "進捗だけをメニューバーに表示" "compactStatusTitle"
check_pair "minimal low-memory concept" "コンセプトはミニマル、省メモリ" "--no-video"
check_pair "streaming cache" "軽いストリーミングバッファ" "--cache-secs=120"
check_pair "mpv playback log" "mpv.log" "--log-file"
check_pair "focus loop concept" "集中用の1曲ループ" 'menuItemWithTitle:@"Shuffle"'
check_pair "shuffle loop" '`Shuffle`' "playOmakaseLoop"
check_pair "pause semantics" '`Pause`は同じ曲の同じ位置から戻る' '@"Pause"'
check_pair "stop semantics" '`Stop`は再生を終了' 'menuItemWithTitle:@"Stop"'
check_pair "timer keeps elapsed playback" "開始からの合計時間としてタイマーを延長" "selectedDuration <= elapsed"
check_pair "Intel and Apple Silicon Homebrew support" "brew install jq mpv yt-dlp" '@"/usr/local/bin"'

echo "README contract checks passed."
