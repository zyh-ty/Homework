#!/bin/bash
# 一键产出可分发 DMG：universal 构建 → 组装 .app → 签名 → 带背景与图标布局的安装窗口
#   ./scripts/make-dmg.sh
# 环境变量：
#   VERSION=1.0                 版本号（写入 Info.plist 与文件名）
#   ARCHS=universal|native      默认 universal（Intel + Apple Silicon）
#   SIGN_IDENTITY=auto|"证书名"|-   默认 auto，交给 build-app.sh 处理
#   SKIP_BUILD=1                复用已有 build/每日作业.app（只重做 DMG，调版式时用）
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="每日作业"
VOL_NAME="每日作业"
VERSION="${VERSION:-1.0}"
ARCHS="${ARCHS:-universal}"
SIGN_IDENTITY="${SIGN_IDENTITY:-auto}"
SKIP_BUILD="${SKIP_BUILD:-0}"

WIDTH=660
HEIGHT=420
ICON_APP_X=170
ICON_APP_Y=210
ICON_DST_X=490
ICON_DST_Y=210
ICON_SIZE=128

BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME-$VERSION-$ARCHS.dmg"
BG="$BUILD_DIR/dmg-background.png"

WORK="$(mktemp -d)"
cleanup() {
    [ -d "/Volumes/$VOL_NAME" ] && hdiutil detach "/Volumes/$VOL_NAME" -force -quiet 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

if [ "$SKIP_BUILD" = "1" ] && [ -d "$APP" ]; then
    echo "==> 1/5 跳过构建，复用 $APP"
else
    echo "==> 1/5 构建 .app（ARCHS=${ARCHS}）"
    ARCHS="$ARCHS" SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" ./scripts/build-app.sh release
fi

echo "==> 2/5 渲染安装窗口背景（${WIDTH}×${HEIGHT}，1x + 2x + HiDPI TIFF）"
swift scripts/make-dmg-background.swift "$BG" "$WIDTH" "$HEIGHT"

echo "==> 3/5 准备暂存目录"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
# Finder 图标视图只按「点 = 像素」画位图背景，必须用双分辨率 TIFF，否则 Retina 上会放大两倍
cp "${BG%.png}.tiff" "$STAGE/.background/background.tiff"
cp "$BG" "$STAGE/.background/background.png"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
fi

echo "==> 4/5 写入窗口布局（背景图 / 图标位置 / 侧边栏隐藏）"
RW_DMG="$WORK/layout.dmg"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null
MOUNT_DIR="$(hdiutil attach "$RW_DMG" -nobrowse -noautoopen \
    | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
[ -n "$MOUNT_DIR" ] || { echo "挂载失败"; exit 1; }

layout_ok=1
osascript <<APPLESCRIPT || layout_ok=0
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        set the bounds of container window to {240, 180, $(($WIDTH + 240)), $(($HEIGHT + 180))}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $ICON_SIZE
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.tiff"
        set position of item "$APP_NAME.app" to {$ICON_APP_X, $ICON_APP_Y}
        set position of item "Applications" to {$ICON_DST_X, $ICON_DST_Y}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

if [ "$layout_ok" = "1" ]; then
    echo "    布局已写入"
else
    echo "    ⚠️  Finder 布局写入失败（可能缺自动化权限），继续产出无布局的 DMG"
fi

sync
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
[ -f "$MOUNT_DIR/.DS_Store" ] && echo "    .DS_Store 已生成" || echo "    ⚠️  未生成 .DS_Store"
hdiutil detach "$MOUNT_DIR" -quiet

echo "==> 5/5 压缩为只读 DMG"
rm -f "$DMG"
hdiutil convert "$RW_DMG" -ov -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

echo "==> 完成：${DMG}（$(du -h "$DMG" | cut -f1)）"
