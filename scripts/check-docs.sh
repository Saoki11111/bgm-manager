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

check_pair "URL add flow" "URL追加..." "URL追加"
check_pair "song submenu" "曲を選ぶ" "曲を選ぶ"
check_pair "song management submenu" "曲を管理" "曲を管理"
check_pair "song rename" "表示名変更" "表示名を変更"
check_pair "song delete" "削除" "曲を削除"
check_pair "three-hour default" "デフォルトでは、3時間タイマー" "self.duration = 10800"
check_pair "compact progress display" "進捗だけをメニューバーに表示" "compactStatusTitle"
check_pair "minimal low-memory concept" "コンセプトはミニマル、省メモリ" "--no-video"
check_pair "streaming cache" "軽いストリーミングバッファ" "--cache-secs=120"
check_pair "mpv playback log" "mpv.log" "--log-file"
check_pair "focus loop concept" "集中用の1曲ループ" 'menuItemWithTitle:@"おまかせ"'
check_pair "omakase loop" "おまかせループ" "playOmakaseLoop"
check_pair "pause semantics" "一時停止は同じ曲の同じ位置から戻る" '@"一時停止"'
check_pair "stop semantics" "停止は再生を終了" 'menuItemWithTitle:@"停止"'

echo "README contract checks passed."
