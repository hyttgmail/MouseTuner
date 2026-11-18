#!/bin/zsh
# 生成 Xcode 工程并编译 Release 版，产物在 build/MouseTuner.app
set -euo pipefail
cd "$(dirname "$0")"

# 先退出正在运行的旧版本，否则下面会删掉它正在使用的 App 包
osascript -e 'quit app "MouseTuner"' 2>/dev/null || true

xcodegen generate --quiet
# Extra arguments go to xcodebuild, e.g. without the author's certificate: ./build.sh CODE_SIGN_IDENTITY=-
xcodebuild -project MouseTuner.xcodeproj -scheme MouseTuner -configuration Release \
  -derivedDataPath build/DerivedData build -quiet "$@"

rm -rf build/MouseTuner.app
cp -R build/DerivedData/Build/Products/Release/MouseTuner.app build/
echo "✅ build/MouseTuner.app"
