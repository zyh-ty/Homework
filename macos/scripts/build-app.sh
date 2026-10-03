#!/bin/bash
# 构建「每日作业.app」（原生 macOS 版）
#   ./scripts/build-app.sh            发布构建
#   ./scripts/build-app.sh debug      调试构建
# 环境变量：
#   ARCHS=universal|native            默认 universal（Intel + Apple Silicon）
#   SIGN_IDENTITY=auto|"证书名"|-     默认 auto：挑钥匙串里的 Apple Development，没有则 ad-hoc
#   VERSION=1.0                       写进 Info.plist 的版本号
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP_NAME="每日作业"
BUNDLE_ID="local.zyh.homework"
VERSION="${VERSION:-1.0}"
ARCHS="${ARCHS:-universal}"
SIGN_IDENTITY="${SIGN_IDENTITY:-auto}"

BUILD_ARGS=(-c "$CONFIG")
if [ "$ARCHS" = "universal" ]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP="$PWD/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/HomeworkMac" "$APP/Contents/MacOS/HomeworkMac"
chmod +x "$APP/Contents/MacOS/HomeworkMac"

# 资源（班徽 / 图标）
cp Sources/HomeworkMac/Resources/badge.png "$APP/Contents/Resources/badge.png"
if [ -d "$BIN_DIR/HomeworkMac_HomeworkMac.bundle" ]; then
    cp -R "$BIN_DIR/HomeworkMac_HomeworkMac.bundle" "$APP/Contents/Resources/"
fi
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>HomeworkMac</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsUsageDescription</key><string>读取系统日历中的「中国大陆节假日」，用于识别法定节假日与调休上课日</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>读取系统日历中的「中国大陆节假日」，用于识别法定节假日与调休上课日</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>南京市鼓楼区班级「每日作业」</string>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
</dict>
</plist>
PLIST

if [ "$SIGN_IDENTITY" = "auto" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)"
    [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="-"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> ad-hoc 签名（钥匙串里没有 Apple Development 证书）"
else
    echo "==> 签名：$SIGN_IDENTITY"
fi
codesign --force --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Resources/HomeworkMac_HomeworkMac.bundle" >/dev/null 2>&1 || true
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP" && echo "==> 签名校验通过"
lipo -archs "$APP/Contents/MacOS/HomeworkMac" | sed 's/^/==> 架构：/'
echo "==> 已生成 $APP"
