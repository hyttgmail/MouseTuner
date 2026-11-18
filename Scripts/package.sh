#!/bin/zsh
# 打包可分发的 DMG：Developer ID 签名 → 公证 App 并附上票据 → 生成 DMG → 签名、公证 DMG 并附上票据 → Gatekeeper 检查
# 产物：build/MouseTuner.dmg
# 前提：钥匙串里有「Developer ID Application」证书，并用 notarytool store-credentials 存过名为 MouseTuner-notary 的凭据
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=23H5ZX4T2P
IDENTITY="Developer ID Application: PENG WANG ($TEAM_ID)"
NOTARY_PROFILE=MouseTuner-notary
WORK=build/package

rm -rf "$WORK"
mkdir -p "$WORK"

echo "▸ 归档"
xcodegen generate --quiet
xcodebuild -project MouseTuner.xcodeproj -scheme MouseTuner -configuration Release \
  -archivePath "$WORK/MouseTuner.xcarchive" archive -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM=$TEAM_ID \
  OTHER_CODE_SIGN_FLAGS=--timestamp

echo "▸ 导出 Developer ID 版本"
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$WORK/MouseTuner.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" -quiet
APP="$WORK/export/MouseTuner.app"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
codesign --verify --deep --strict "$APP"

echo "▸ 公证 App"
ditto -c -k --keepParent "$APP" "$WORK/MouseTuner.zip"
xcrun notarytool submit "$WORK/MouseTuner.zip" --keychain-profile $NOTARY_PROFILE --wait
xcrun stapler staple "$APP"

echo "▸ 生成 DMG"
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/MouseTuner.app"
ln -s /Applications "$WORK/dmg/Applications"
DMG="build/MouseTuner.dmg"
rm -f "$DMG"
hdiutil create -volname "MouseTuner" -srcfolder "$WORK/dmg" -fs APFS -format ULFO -ov "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "▸ 公证 DMG"
xcrun notarytool submit "$DMG" --keychain-profile $NOTARY_PROFILE --wait
xcrun stapler staple "$DMG"

echo "▸ Gatekeeper 检查"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
echo "✅ $DMG"
