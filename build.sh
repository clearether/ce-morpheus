#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
bin="$(swift build -c release --show-bin-path)/ce-morpheus"

app="build/ce-morpheus.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/ce-morpheus"
cp Info.plist "$app/Contents/Info.plist"
# 名前を明示し、1 枚でも欠けていれば cp を失敗させて止める（ワイルドカードだと欠落に気づけない）。
for state in on off unknown; do
    cp "Resources/ampoule-$state.png" "Resources/ampoule-$state@2x.png" "$app/Contents/Resources/"
done
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --sign - --force "$app"
echo "built: $app"
