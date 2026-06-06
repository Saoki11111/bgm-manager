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

check_pair "URL add flow" "URLを追加..." "URLを追加"
check_pair "song submenu" "曲を選ぶ" "曲を選ぶ"
check_pair "song management submenu" "曲を管理" "曲を管理"
check_pair "song rename" "表示名変更" "表示名を変更"
check_pair "song delete" "削除" "曲を削除"
check_pair "source-duration default" "自動（曲の長さ）" "自動（曲の長さ）"
check_pair "compact progress display" "進捗だけをメニューバーに表示" "compactStatusTitle"
check_pair "minimal low-memory concept" "コンセプトはミニマル、省メモリ" "--no-video"
check_pair "short streaming cache" "--cache-secs=10" "--cache-secs=10"
check_pair "random current title" "ランダム再生中も" "displayTitle"
check_pair "previous track" "前の曲" "previousTrack"
check_pair "next track" "次の曲" "nextTrack"
check_pair "pause semantics" "一時停止は同じ曲の同じ位置から戻る" "一時停止（位置を残す）"
check_pair "stop semantics" "停止は再生を終了" "停止（再生を終了）"

echo "README contract checks passed."
