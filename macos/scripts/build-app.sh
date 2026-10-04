#!/bin/bash
# 构建「每日作业.app」（原生 macOS 版）
#   ./scripts/build-app.sh            发布构建
#   ./scripts/build-app.sh debug      调试构建
# 环境变量：
#   ARCHS=universal|native            默认 universal（Intel + Apple Silicon）
#   SIGN_IDENTITY=auto|"证书名"|-     默认 auto：挑钥匙串里的 Apple Development，没有则 ad-hoc
#   VERSION=1.0                       写进 app 的版本号
#
# 单一构建路径：xcodebuild 读 macos/project.yml 生成的工程。
# Info.plist / entitlements / 资源 / 版本号都来自 project.yml（Support/ 由 xcodegen 生成），
# 这里不再手写第二份。签名交给脚本：先用 CODE_SIGNING_ALLOWED=NO 编译，
# 再按 SIGN_IDENTITY 用 codesign 签（不依赖 Xcode 里的团队配置）。
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG_INPUT="${1:-release}"
case "$CONFIG_INPUT" in
    release|Release) XC_CONFIG=Release ;;
    debug|Debug)     XC_CONFIG=Debug ;;
    *) echo "未知配置：${CONFIG_INPUT}（用 release 或 debug）"; exit 1 ;;
esac

APP_NAME="每日作业"
VERSION="${VERSION:-1.0}"
ARCHS="${ARCHS:-universal}"
SIGN_IDENTITY="${SIGN_IDENTITY:-auto}"

if [ "$ARCHS" = "universal" ]; then
    XC_ARCHS="arm64 x86_64"
else
    XC_ARCHS="$(uname -m)"
fi

command -v xcodegen >/dev/null \
    || { echo "需要 xcodegen：brew install xcodegen（project.yml 是工程定义的唯一来源）"; exit 1; }
command -v xcodebuild >/dev/null \
    || { echo "需要 Xcode 命令行工具：xcode-select --install"; exit 1; }

# 每次都重新生成：xcodegen 按目录收集源文件，新增/删除 .swift 后不重跑就会漏文件
echo "==> xcodegen generate"
xcodegen generate --quiet

DERIVED="build/xcode"
echo "==> xcodebuild -configuration $XC_CONFIG ARCHS=\"$XC_ARCHS\""
xcodebuild \
    -project HomeworkMac.xcodeproj \
    -scheme HomeworkApp \
    -configuration "$XC_CONFIG" \
    -derivedDataPath "$DERIVED" \
    ARCHS="$XC_ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGNING_ALLOWED=NO \
    build \
    | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true

BUILT="$(find "$DERIVED/Build/Products/$XC_CONFIG" -maxdepth 1 -name "*.app" -print -quit)"
[ -n "$BUILT" ] || { echo "没找到构建产物（$DERIVED/Build/Products/$XC_CONFIG/*.app）"; exit 1; }

APP="$PWD/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
# ditto 保留 bundle 结构与资源（cp -R 会丢扩展属性）
ditto "$BUILT" "$APP"

if [ "$SIGN_IDENTITY" = "auto" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)"
    [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="-"
fi

SIGN_OPTS=()
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> ad-hoc 签名（钥匙串里没有 Apple Development 证书）"
else
    echo "==> 签名：${SIGN_IDENTITY}（启用 hardened runtime）"
    SIGN_OPTS+=(--options runtime)
fi

# 先签内嵌的 bundle（SwiftPM 资源包），再签整包
for nested in "$APP/Contents/Resources"/*.bundle; do
    [ -d "$nested" ] || continue
    codesign --force "${SIGN_OPTS[@]}" --sign "$SIGN_IDENTITY" "$nested" >/dev/null 2>&1 || true
done

ENTITLEMENTS="Support/HomeworkMac.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force "${SIGN_OPTS[@]}" --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force "${SIGN_OPTS[@]}" --sign "$SIGN_IDENTITY" "$APP"
fi

codesign --verify --strict "$APP" && echo "==> 签名校验通过"
lipo -archs "$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")" \
    | sed 's/^/==> 架构：/'
echo "==> 已生成 $APP"
