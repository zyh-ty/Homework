#!/bin/bash
# 从 main 导出「只有 macOS 版」的分支（默认 features/Mac）并推送
#   ./scripts/export-mac-branch.sh             同步并推送
#   DRY=1 ./scripts/export-mac-branch.sh       只显示会改什么，不提交不推送
#
# 分支模型：mac-only 分支自己保存根 README/.gitignore 与删除记录，
# 每次只把 macos/、fixtures/、LICENSE 从 SRC 刷新过来 —— 因此每次都是快进推送。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SRC="${SRC:-main}"
LOCAL_BRANCH="${LOCAL_BRANCH:-mac-only}"
REMOTE="${REMOTE:-origin}"
REMOTE_BRANCH="${REMOTE_BRANCH:-features/Mac}"
DRY="${DRY:-0}"
EXPORT_PATHS=(macos fixtures LICENSE)

git rev-parse --verify --quiet "$LOCAL_BRANCH" >/dev/null \
    || { echo "本地分支 $LOCAL_BRANCH 不存在：先按 README 的说明初始化一次"; exit 1; }

# 先把远端分支拉到本地：否则本地落后时，推送会被拒（non-fast-forward）
if git fetch --quiet "$REMOTE" "$REMOTE_BRANCH:$LOCAL_BRANCH" 2>/dev/null; then
    :
elif git fetch --quiet "$REMOTE" "$REMOTE_BRANCH" 2>/dev/null; then
    # 远端分支不能直接快进本地（历史无关）：以远端为准重建，导出分支的提交历史本就可丢弃
    git branch -f "$LOCAL_BRANCH" FETCH_HEAD
fi

WORK="$(mktemp -d)/export"
cleanup() {
    git worktree remove --force "$WORK" >/dev/null 2>&1 || true
    rm -rf "$(dirname "$WORK")"
}
trap cleanup EXIT

git worktree add --quiet --detach "$WORK" "$LOCAL_BRANCH"
cd "$WORK"
git checkout "$SRC" -- "${EXPORT_PATHS[@]}"

# xcodegen 生成物必须被忽略：分支自己的 .gitignore 会随手改，
# 这里保证这几行始终在（且只补缺失的行，不动分支上已有的写法）
ensure_ignored() {
    local entry="$1"
    grep -qxF "$entry" .gitignore 2>/dev/null && return 0
    printf '%s\n' "$entry" >> .gitignore
}
ensure_ignored "# xcodegen 生成物（唯一来源是 macos/project.yml）"
ensure_ignored "HomeworkMac.xcodeproj/"
ensure_ignored "Support/"
ensure_ignored ".swiftpm/"

git add -A

if git diff --cached --quiet; then
    echo "==> 已是最新（${EXPORT_PATHS[*]} 与 $SRC 一致），无需同步"
    exit 0
fi

git diff --cached --stat
if [ "$DRY" = "1" ]; then
    echo "==> DRY=1，未提交、未推送"
    exit 0
fi

git -c user.name="$(git -C "$ROOT" log -1 --format=%an "$SRC")" \
    -c user.email="$(git -C "$ROOT" log -1 --format=%ae "$SRC")" \
    commit -q -m "chore: 同步 macOS 版（$SRC $(git -C "$ROOT" log -1 --format=%h "$SRC")）"

echo "==> 推送 $LOCAL_BRANCH → $REMOTE/$REMOTE_BRANCH"
git push "$REMOTE" "HEAD:refs/heads/$REMOTE_BRANCH"
echo "==> 完成：$REMOTE/$REMOTE_BRANCH = $(git log -1 --format=%h)"
