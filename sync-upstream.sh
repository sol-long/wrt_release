#!/usr/bin/env bash
# ============================================================
# fork 同步脚本
#   用法: ./sync-upstream.sh
#   作用: 将 main 同步到上游，然后按层级 rebase 所有分支
#
#   分支层级:
#     main (上游跟踪 + 自定义精简)
#       └── lite (+ 精简增强 + dl cache)
#             ├── lite_nikki (+ nikki 代理)
#             │     └── lite_nikki_UA3F (+ UA3F)
#             │           └── lite_bandix_nikki_UA3F (+ bandix + argon)
#             ├── lite_bandix (+ bandix + argon, 无代理)
#             │     └── lite_bandix_UA3F (+ UA3F)
#             └── lite_bandix_openclash (+ openclash + bandix + argon)
#                   └── lite_bandix_openclash_UA3F (+ UA3F)
# ============================================================
set -euo pipefail

UPSTREAM_URL="https://github.com/ZqinKing/wrt_release.git"
PATCH_FILE="../custom.patch"

# 下级分支及其父分支 (按拓扑序，父在先)
declare -A CHILD_OF=(
    [lite]=main
    [lite_nikki]=lite
    [lite_nikki_UA3F]=lite_nikki
    [lite_bandix_nikki_UA3F]=lite_nikki_UA3F
    [lite_bandix]=lite
    [lite_bandix_UA3F]=lite_bandix
    [lite_bandix_openclash]=lite
    [lite_bandix_openclash_UA3F]=lite_bandix_openclash
)

# 处理顺序 (保证父先于子被 rebase)
ORDERED_BRANCHES=(
    lite
    lite_nikki
    lite_nikki_UA3F
    lite_bandix_nikki_UA3F
    lite_bandix
    lite_bandix_UA3F
    lite_bandix_openclash
    lite_bandix_openclash_UA3F
)

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- 1. 确保 upstream 已配置 ----
setup_upstream() {
    if ! git remote get-url upstream &>/dev/null; then
        log_info "添加 upstream remote: $UPSTREAM_URL"
        git remote add upstream "$UPSTREAM_URL"
    else
        local current_url
        current_url=$(git remote get-url upstream)
        if [ "$current_url" != "$UPSTREAM_URL" ]; then
            log_warn "upstream 地址不匹配，更新中..."
            git remote set-url upstream "$UPSTREAM_URL"
        fi
    fi
}

# ---- 2. 保存当前分支 ----
save_branch() {
    ORIG_BRANCH=$(git branch --show-current)
    log_info "当前分支: $ORIG_BRANCH"
}

# ---- 3. 同步 main -> 上游 (patch 方式) ----
sync_main() {
    log_info "拉取上游最新..."
    git fetch --no-tags upstream

    log_info "切换到 main..."
    git checkout main

    log_info "生成自定义补丁 (相对 upstream/main)..."
    if git diff upstream/main...main > "$PATCH_FILE"; then
        if [ -s "$PATCH_FILE" ]; then
            log_info "补丁已保存: $PATCH_FILE ($(wc -l < "$PATCH_FILE") 行)"
        else
            log_warn "补丁为空，main 和上游完全一致"
        fi
    fi

    log_info "重置 main 到 upstream/main..."
    git reset --hard upstream/main

    if [ -s "$PATCH_FILE" ]; then
        log_info "应用补丁 (--3way 合并)..."
        if git apply --3way "$PATCH_FILE"; then
            log_info "补丁应用成功"
        else
            log_error "补丁冲突！请手动解决。补丁文件: $PATCH_FILE"
            log_error "解决后: git commit -a -m 'sync upstream' && git push origin main -f"
            exit 1
        fi
    fi

    log_info "提交并推送 main..."
    git commit -a -m "sync: rebase onto upstream/main" || log_warn "main 无变更可提交"
    git push origin main --force-with-lease
}

# ---- 4. 逐级 rebase 各分支 ----
rebase_children() {
    for branch in "${ORDERED_BRANCHES[@]}"; do
        local parent="${CHILD_OF[$branch]}"
        log_info "--- ${parent} → ${branch} ---"

        if ! git rev-parse --verify "origin/$branch" &>/dev/null; then
            log_warn "跳过: 远程没有 $branch"
            continue
        fi

        git checkout "$branch"

        if git rebase "$parent"; then
            log_info "$branch rebase 成功"
        else
            log_error "$branch rebase 到 $parent 失败，请手动解决冲突"
            log_error "解决后: git rebase --continue && git push origin $branch --force-with-lease"
            exit 1
        fi

        git push origin "$branch" --force-with-lease
    done
}

# ---- 5. 切回原分支 ----
restore_branch() {
    log_info "切回原分支: $ORIG_BRANCH"
    git checkout "$ORIG_BRANCH"
}

# ==============================
# 主流程
# ==============================
log_info "======== Fork 同步开始 ========"
setup_upstream
save_branch
sync_main
rebase_children
restore_branch
log_info "======== 同步完成 ========"
[ -s "$PATCH_FILE" ] && log_info "补丁文件保留: $PATCH_FILE (可手动删除)"
