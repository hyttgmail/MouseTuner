#!/bin/zsh
# 打包 Mac App Store 版本：归档 → 用 Apple Distribution 证书重新签名并导出 .pkg（或直接上传到 App Store Connect）
# 用法：Scripts/appstore.sh          只在本地生成 build/appstore/export/MouseTuner.pkg
#       Scripts/appstore.sh upload   导出后直接上传
# 前提：Xcode › 设置 › Accounts 登录了团队 23H5ZX4T2P 的 Apple ID。导出时 Xcode 会按需注册 Bundle ID、
#       创建 Apple Distribution / Mac Installer Distribution 证书和 Mac App Store 描述文件（-allowProvisioningUpdates）。
#       上传前 App Store Connect 里要先建好 com.alphapengwang.MouseTuner 的 App 记录。
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=23H5ZX4T2P
DESTINATION=${1:-export}
WORK=build/appstore

rm -rf "$WORK"
mkdir -p "$WORK"

echo "▸ 归档"
xcodegen generate --quiet
xcodebuild -project MouseTuner.xcodeproj -scheme MouseTuner -configuration Release \
  -archivePath "$WORK/MouseTuner.xcarchive" archive -quiet

APP="$WORK/MouseTuner.xcarchive/Products/Applications/MouseTuner.app"
# 上传时 App Store Connect 会拒绝引用私有符号的二进制，先在本地拦下来
if nm -u "$APP/Contents/MacOS/MouseTuner" | grep -q -E 'CGEventCopyIOHIDEvent|IOHIDEventGetSenderID'; then
  echo "✗ 二进制引用了私有符号" >&2
  exit 1
fi

echo "▸ 导出（$DESTINATION）"
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$WORK/MouseTuner.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" -allowProvisioningUpdates

if [[ $DESTINATION == upload ]]; then
  echo "✅ 已上传，几分钟后出现在 App Store Connect › TestFlight"
else
  echo "✅ $WORK/export/MouseTuner.pkg"
fi
