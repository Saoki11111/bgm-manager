#!/usr/bin/env bash
set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="$SCRIPT_DIR/../data/bgm-list.json"
MODE="${1:-play}"

for cmd in jq mpv yt-dlp python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd が見つかりません。brew install jq mpv yt-dlp してください。"
        exit 1
    fi
done

ensure_db() {
    mkdir -p "$(dirname "$DB_FILE")"
    [ -f "$DB_FILE" ] || printf '[]\n' > "$DB_FILE"
}

manage() {
    ensure_db
    while true; do
        clear
        echo "BGM Manager"
        echo "-----------"
        jq -r 'to_entries[] | "\(.key + 1)) \(.value.label)"' "$DB_FILE"
        echo
        echo "番号) 再生  r) 全曲ランダム再生  a) 追加  d) 削除  q) 終了"
        if ! read -r -p "> " choice; then
            sleep 1
            continue
        fi
        if [ -z "$choice" ]; then
            sleep 0.2
            continue
        fi
        case "$choice" in
            [0-9]*)
                list_length="$(jq 'length' "$DB_FILE")"
                if [ "$choice" -ge 1 ] && [ "$choice" -le "$list_length" ]; then
                    read -r -p "再生時間 (Enterで1h): " duration
                    [ -z "$duration" ] && duration="1h"
                    play "$choice" --time "$duration"
                    [ -t 0 ] && stty sane 2>/dev/null || true
                else
                    echo "番号が範囲外です: $choice (1-$list_length)"
                    sleep 1
                fi
                ;;
            r)
                read -r -p "再生時間 (Enterで1h): " duration
                [ -z "$duration" ] && duration="1h"
                play --time "$duration"
                [ -t 0 ] && stty sane 2>/dev/null || true
                ;;
            a)
                read -r -p "URL: " url
                read -r -p "Name: " label
                tmp="$(mktemp)"
                jq --arg label "$label" --arg url "$url" '. += [{label: $label, url: $url}]' "$DB_FILE" > "$tmp" && mv "$tmp" "$DB_FILE"
                ;;
            d)
                read -r -p "削除番号: " num
                if [[ "$num" =~ ^[0-9]+$ ]]; then
                    tmp="$(mktemp)"
                    jq "del(.[$((num - 1))])" "$DB_FILE" > "$tmp" && mv "$tmp" "$DB_FILE"
                fi
                ;;
            q) exit 0 ;;
        esac
    done
}

is_url() {
    [[ "$1" =~ ^https?:// || "$1" =~ ^(www\.)?(youtube\.com|youtu\.be)/ ]]
}

parse_duration() {
    local raw="$1"
    local hours=0
    local minutes=0
    local seconds=0

    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$raw"
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+):([0-9]{1,2}):([0-9]{1,2})$ ]]; then
        hours="${BASH_REMATCH[1]}"
        minutes="${BASH_REMATCH[2]}"
        seconds="${BASH_REMATCH[3]}"
        if [ "$minutes" -ge 60 ] || [ "$seconds" -ge 60 ]; then
            return 1
        fi
        printf '%s\n' $((10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds))
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+):([0-9]{1,2})$ ]]; then
        minutes="${BASH_REMATCH[1]}"
        seconds="${BASH_REMATCH[2]}"
        if [ "$seconds" -ge 60 ]; then
            return 1
        fi
        printf '%s\n' $((10#$minutes * 60 + 10#$seconds))
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+)h([0-9]+m?)?$ ]]; then
        hours="${BASH_REMATCH[1]}"
        minutes="${BASH_REMATCH[2]%m}"
        [ -z "$minutes" ] && minutes=0
        printf '%s\n' $((10#$hours * 3600 + 10#$minutes * 60))
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+)時間([0-9]+分?)?$ ]]; then
        hours="${BASH_REMATCH[1]}"
        minutes="${BASH_REMATCH[2]%分}"
        [ -z "$minutes" ] && minutes=0
        printf '%s\n' $((10#$hours * 3600 + 10#$minutes * 60))
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+)m$ ]]; then
        printf '%s\n' $((10#${BASH_REMATCH[1]} * 60))
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+)分$ ]]; then
        printf '%s\n' $((10#${BASH_REMATCH[1]} * 60))
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+)s$ ]]; then
        printf '%s\n' $((10#${BASH_REMATCH[1]}))
        return 0
    fi

    if [[ "$raw" =~ ^([0-9]+)秒$ ]]; then
        printf '%s\n' $((10#${BASH_REMATCH[1]}))
        return 0
    fi

    return 1
}

enrich_playlist_titles() {
    local json_file="$1"
    local count
    local i
    local url
    local title
    local tmp

    count="$(jq 'length' "$json_file")"
    i=0
    while [ "$i" -lt "$count" ]; do
        url="$(jq -r ".[$i].url" "$json_file")"
        title="$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null | head -n 1)"
        if [ -n "$title" ]; then
            tmp="$(mktemp)"
            jq --arg title "$title" ".[$i].label = \$title" "$json_file" > "$tmp" && mv "$tmp" "$json_file"
        fi
        i=$((i + 1))
    done
}

usage() {
    echo "BGM Manager"
    echo "-----------"
    echo "使い方:"
    echo "  ./scripts/bgm-manager.sh manage"
    echo "  ./scripts/bgm-manager.sh play"
    echo "  ./scripts/bgm-manager.sh play [番号] [時間]"
    echo "  ./scripts/bgm-manager.sh play URL [時間]"
    echo "  ./scripts/bgm-manager.sh play --url URL --time 1h"
    echo
    echo "Options:"
    echo "  --url URL          リストに登録せずURLを直接再生"
    echo "  --time 時間        指定時間で自動終了 (例: 1h, 90m, 1h30m, 1時間, 1:00:00)"
    echo "  --duration 秒数    指定秒数で自動終了 (--time と同じ扱い)"
    echo "  --loop            ループ再生 (default)"
    echo "  --no-loop         ループしない"
    echo "  --random          次の曲をランダムに選ぶ (default)"
    echo "  --no-random       リスト順で再生"
}

play() {
    ensure_db
    local list_length
    list_length=$(jq 'length' "$DB_FILE")

    local target_index=""
    local direct_url=""
    local duration_raw="0"
    local duration_limit="0"
    local loop_enabled=1
    local random_enabled=1
    local random_explicit=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --url)
                if [ "$#" -lt 2 ]; then
                    echo "--url にはURLが必要です。"
                    exit 1
                fi
                direct_url="$2"
                shift 2
                ;;
            --time|--duration|--seconds)
                if [ "$#" -lt 2 ]; then
                    echo "$1 には時間が必要です。"
                    exit 1
                fi
                duration_raw="$2"
                shift 2
                ;;
            --loop)
                loop_enabled=1
                shift
                ;;
            --no-loop)
                loop_enabled=0
                shift
                ;;
            --random|--shuffle)
                random_enabled=1
                random_explicit=1
                shift
                ;;
            --no-random|--no-shuffle)
                random_enabled=0
                random_explicit=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "不明なオプションです: $1"
                usage
                exit 1
                ;;
            *)
                if [ -z "$direct_url" ] && is_url "$1"; then
                    direct_url="$1"
                elif [ -z "$target_index" ] && [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le "$list_length" ]; then
                    target_index="$1"
                elif duration_limit="$(parse_duration "$1")"; then
                    duration_raw="$1"
                else
                    echo "解釈できない引数です: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$direct_url" ] && [ "$list_length" -eq 0 ]; then
        echo "曲リストが空です。URLを渡すか、./scripts/bgm-manager.sh manage で追加してください。"
        exit 1
    fi

    if ! duration_limit="$(parse_duration "$duration_raw")"; then
        echo "時間指定を解釈できません: $duration_raw"
        echo "例: 1h, 90m, 1h30m, 1時間, 1時間30分, 1:00:00"
        exit 1
    fi
    if [ -n "$target_index" ] && [ "$random_explicit" -eq 0 ]; then
        random_enabled=0
    fi

    work_dir="$(mktemp -d)"
    playlist="$work_dir/playlist.txt"
    playlist_json="$work_dir/playlist.json"
    current_index_file="$work_dir/current-index"
    random_state_file="$work_dir/random-state"
    socket="$work_dir/mpv.sock"
    stty_state=""
    mpv_pid=""
    timer_pid=""
    playlist_start=0

    cleanup() {
        [ -n "$stty_state" ] && stty "$stty_state" 2>/dev/null || true
        [ -t 1 ] && printf '\033[?25h\033[?1049l\033[0m' || true
        [ -n "$timer_pid" ] && kill "$timer_pid" 2>/dev/null || true
        [ -n "$mpv_pid" ] && kill "$mpv_pid" 2>/dev/null || true
        rm -rf "$work_dir"
    }
    trap cleanup EXIT INT TERM

    # プレイリストの作成
    if [ -n "$direct_url" ]; then
        direct_title="$(yt-dlp --no-playlist --get-title "$direct_url" 2>/dev/null | head -n 1)"
        [ -z "$direct_title" ] && direct_title="$direct_url"
        jq -n --arg label "$direct_title" --arg url "$direct_url" '[{label: $label, url: $url}]' > "$playlist_json"
    elif [[ "$target_index" =~ ^[0-9]+$ ]] && [ "$target_index" -ge 1 ] && [ "$target_index" -le "$list_length" ]; then
        # 指定曲から再生を始めるが、再生中に選曲できるよう登録リスト全体を表示する。
        jq '[.[] | {label, url}]' "$DB_FILE" > "$playlist_json"
        playlist_start=$((target_index - 1))
    elif [ -n "$target_index" ]; then
        echo "番号が範囲外です: $target_index (1-$list_length)"
        exit 1
    else
        # 全曲を抽出
        jq '[.[] | {label, url}]' "$DB_FILE" > "$playlist_json"
    fi
    [ -t 1 ] && printf '\033[?1049h\033[2J\033[H\033[?25l'
    # ループの設定 (単一曲の場合は --loop-file=inf、プレイリストの場合は --loop-playlist)
    local playlist_length
    local loop_opt=""
    local start_opt=""
    local shuffle_opt=""
    playlist_length="$(jq 'length' "$playlist_json")"
    if [ "$random_enabled" -eq 1 ] && [ "$playlist_length" -gt 1 ]; then
        shuffle_opt="--shuffle"
    fi
    jq -r '.[].url' "$playlist_json" > "$playlist"
    playlist_length="$(wc -l < "$playlist")"
    if [ "$loop_enabled" -eq 1 ]; then
        loop_opt="--loop-playlist=inf"
        if [ -s "$playlist" ] && { [ "$playlist_length" -eq 1 ] || { [ -n "$target_index" ] && [ "$random_enabled" -eq 0 ]; }; }; then
            loop_opt="--loop-file=inf"
        fi
    fi
    start_opt="--playlist-start=$playlist_start"
    printf '%s\n' "$playlist_start" > "$current_index_file"
    printf '%s\n' "$random_enabled" > "$random_state_file"

    mpv \
        --no-config \
        --no-video \
        --playlist="$playlist" \
        --load-unsafe-playlists \
        "$start_opt" \
        ${shuffle_opt:+"$shuffle_opt"} \
        ${loop_opt:+"$loop_opt"} \
        --ytdl-format='ba[abr<128]/ba' \
        --ytdl-raw-options='no-playlist=' \
        --input-terminal=no \
        --input-ipc-server="$socket" \
        --msg-level=all=no \
        --term-osd-bar=no \
        --force-window=no \
        --cache=yes \
        --cache-secs=120 \
        --log-file="$work_dir/mpv.log" \
        >/dev/null 2>&1 &
    mpv_pid=$!

    # 自動終了タイマー
    if [ "$duration_limit" -gt 0 ]; then
        (sleep "$duration_limit" && python3 - "$socket" '{"command":["quit"]}' <<'PY' >/dev/null 2>&1
import time
import socket, sys
for _ in range(30):
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.connect(sys.argv[1])
            s.sendall((sys.argv[2] + "\n").encode())
        break
    except OSError:
        time.sleep(0.2)
PY
) &
        timer_pid=$!
    fi

    send_cmd() {
        python3 - "$socket" "$1" <<'PY' >/dev/null 2>&1
import socket, sys
with socket.socket(socket.AF_UNIX) as s:
    s.connect(sys.argv[1])
    s.sendall((sys.argv[2] + "\n").encode())
PY
    }

    play_index() {
        local index="$1"
        local random_state
        if [ "$index" -lt 0 ] || [ "$index" -ge "$playlist_length" ]; then
            return
        fi
        printf '%s\n' "$index" > "$current_index_file"
        random_state="$(cat "$random_state_file" 2>/dev/null || printf '0')"
        send_cmd '{"command":["playlist-unshuffle"]}'
        send_cmd "{\"command\":[\"playlist-play-index\",$index]}"
        if [ "$random_state" -eq 1 ]; then
            send_cmd '{"command":["playlist-shuffle"]}'
        fi
    }

    play_next_index() {
        send_cmd '{"command":["playlist-next","force"]}'
    }

    toggle_random() {
        local random_state
        random_state="$(cat "$random_state_file" 2>/dev/null || printf '0')"
        if [ "$random_state" -eq 1 ]; then
            printf '0\n' > "$random_state_file"
            send_cmd '{"command":["playlist-unshuffle"]}'
        else
            printf '1\n' > "$random_state_file"
            send_cmd '{"command":["playlist-shuffle"]}'
        fi
    }

    status() {
        python3 - "$socket" "$playlist_json" "$duration_limit" "$start_epoch" "$current_index_file" "$random_state_file" <<'PY'
import json, socket, sys, time

def fmt(v):
    if not isinstance(v, (int, float)):
        return "--:--"
    v = max(0, int(v))
    h, r = divmod(v, 3600)
    m, s = divmod(r, 60)
    return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"

socket_path, playlist_path = sys.argv[1], sys.argv[2]
duration_limit, start_epoch, index_path, random_path = int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6]
with open(playlist_path, encoding="utf-8") as f:
    playlist = json.load(f)
try:
    with open(index_path, encoding="utf-8") as f:
        current_pos = int(f.read().strip())
except (OSError, ValueError):
    current_pos = 0
try:
    with open(random_path, encoding="utf-8") as f:
        random_enabled = int(f.read().strip()) == 1
except (OSError, ValueError):
    random_enabled = False

props = {}
try:
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(socket_path)
        f = s.makefile("r", encoding="utf-8")
        for name in ("media-title", "time-pos", "duration", "pause", "path"):
            s.sendall((json.dumps({"command": ["get_property", name]}) + "\n").encode())
            props[name] = json.loads(f.readline()).get("data")
except OSError:
    props = {}

pos = current_pos if 0 <= current_pos < len(playlist) else 0
path = props.get("path")
if path:
    for i, item in enumerate(playlist):
        if item["url"] == path:
            pos = i
            break
label = playlist[pos]["label"] if playlist else "読み込み中"
media_title = props.get("media-title")
if (
    media_title
    and media_title != "-"
    and "watch?v=" not in media_title
    and "youtube.com" not in media_title
    and "youtu.be" not in media_title
    and not media_title.startswith("http")
):
    label = media_title
mark = "一時停止中" if props.get("pause") else ("再生中" if props else "読み込み中")

def line(text=""):
    print(f"\033[2K\r{text}")

line(f"{mark}: {label}")
line(f"曲時間: {fmt(props.get('time-pos'))} / {fmt(props.get('duration'))}")
line(f"ランダム再生: {'on' if random_enabled else 'off'}")
if duration_limit > 0:
    elapsed = max(0, int(time.time()) - start_epoch)
    remaining = max(0, duration_limit - elapsed)
    line(f"タイマー: {fmt(elapsed)} / {fmt(duration_limit)}  残り {fmt(remaining)}")
else:
    elapsed = max(0, int(time.time()) - start_epoch)
    line(f"タイマー: {fmt(elapsed)} / 無制限")

line()
line("リスト:")
for i, item in enumerate(playlist[:9], start=1):
    cursor = ">" if i - 1 == pos else " "
    line(f"{cursor} {i}. {item['label']}")
if len(playlist) > 9:
    line(f"  ... 他 {len(playlist) - 9} 件")
PY
    }

    start_epoch="$(date +%s)"
    [ -t 0 ] && stty_state="$(stty -g)" && stty -echo -icanon min 0 time 10
    while kill -0 "$mpv_pid" 2>/dev/null; do
        [ -t 1 ] && printf '\033[H'
        printf '\033[2K\r🎵 BGM Manager\n'
        printf '\033[2K\r数字: 選曲  >: 次  r: ランダム切替  Space/p: 一時停止  q: 終了\n'
        printf '\033[2K\r----------------------------------------------------\n'
        status
        [ -t 1 ] && printf '\033[J'
        if IFS= read -r -s -t 1 -n 1 key; then
            case "$key" in
                ">"|"") play_next_index ;;
                r) toggle_random ;;
                " "|"p") send_cmd '{"command":["cycle","pause"]}' ;;
                [1-9])
                    if [ "$key" -le "$playlist_length" ]; then
                        play_index "$((key - 1))"
                    fi
                    ;;
                q) send_cmd '{"command":["quit"]}'; break ;;
            esac
        fi
    done

    wait "$mpv_pid" 2>/dev/null || true
}

case "$MODE" in
    manage) manage ;;
    play)   play "${@:2}" ;;
    help|-h|--help) usage ;;
    *)
        usage
        ;;
esac
