#!/bin/bash
# ビルドして /Applications/ce-morpheus.app を入れ替え、起動する。特権は使わない。
set -euo pipefail
cd "$(dirname "$0")"

bundle_id="local.ce-morpheus"
src="build/ce-morpheus.app"
dir="/Applications"
dest="$dir/ce-morpheus.app"

if [ ! -w "$dir" ]; then
    echo "error: $dir に書き込めません（特権は使いません）。" >&2
    exit 1
fi

# 別のアプリを消さないよう、置き換え先が ce-morpheus であることを先に確かめる。
if [ -e "$dest" ]; then
    found="$(plutil -extract CFBundleIdentifier raw "$dest/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$found" != "$bundle_id" ]; then
        echo "error: $dest の CFBundleIdentifier が $bundle_id ではありません（${found:-読めません}）。何も変えずに止めます。" >&2
        exit 1
    fi
fi

./build.sh

# 新版は、今回作った一時ディレクトリの中で用意して検証する（同じボリュームにして mv で入れ替えるため /Applications 内）。
# 終了時に消すのはこのディレクトリだけ。入れ替えに成功したあとは、新版はもう中に無い。
# bash 3.2 は EXIT の trap があると、set -u などで途中終了しても終了値が 0 になることがあるので、最後まで進んだかで決める。
finished=""
work="$(mktemp -d "$dir/.ce-morpheus-install.XXXXXX")"
trap 'rm -rf "$work"; [ -n "$finished" ] || exit 1' EXIT
new="$work/ce-morpheus.app"
ditto "$src" "$new"
if ! codesign --verify --verbose "$new"; then
    echo "error: 新版の署名を確認できませんでした。/Applications にインストール済みの旧版はそのままです。" >&2
    exit 1
fi

# 自分のユーザーで動いているものだけを終了させる。pkill / pgrep の 1 は「該当なし」。
uid="$(id -u)"
pkill -x -U "$uid" ce-morpheus || [ $? -eq 1 ]
gone=""
for _ in $(seq 1 20); do
    rc=0
    pgrep -x -U "$uid" ce-morpheus > /dev/null || rc=$?
    case "$rc" in
        0) sleep 0.25 ;;
        1) gone=1; break ;;
        *)
            echo "error: プロセスを確認できませんでした（pgrep の終了値 ${rc}）。旧版はそのままです。" >&2
            exit 1
            ;;
    esac
done
if [ -z "$gone" ]; then
    echo "error: ce-morpheus が終了しません。旧版はそのままです。" >&2
    exit 1
fi

rm -rf "$dest"
mv "$new" "$dest"
open "$dest"
echo "installed: $dest"
finished=1
