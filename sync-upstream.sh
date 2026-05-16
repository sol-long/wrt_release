#!/usr/bin/env bash
# ============================================================
# fork 同步脚本
#   用法: ./sync-upstream.sh
#   作用: 将 main 分支同步到上游最新，然后 rebase 所有 lite_* 分支
# ============================================================
set -euo pipefail

UPSTREAM_URL="https://github.com/ZqinKing/wrt_release.git"
PATCH_FILE="../custom.patch"
LITE_BRANCHES=(
    lite_nikki
    lite_nikki_UA3F
    lite_bandix_nikki_UA3F
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

# ---- 2. 保存当前分支，切回 main ----
save_and_switch() {
    ORIG_BRANCH=$(git branch --show-current)
    log_info "当前分支: $ORIG_BRANCH，切换到 main"
    git checkout main
}

# ---- 3. 同步 main -> 上游 ----
sync_main() {
    log_info "拉取上游最新..."
    git fetch --no-tags upstream

    log_info "生成自定义补丁 (相对 upstream/main)..."
    git diff upstream/main...main > "$PATCH_FILE"

    if [ ! -s "$PATCH_FILE" ]; then
        log_warn "补丁为空（main 和上游完全一致），跳过应用"
    else
        log_info "补丁已保存到 $PATCH_FILE ($(wc -l < "$PATCH_FILE") 行)"
    fi

    log_info "重置 main 到 upstream/main..."
    git reset --hard upstream/main

    if [ -s "$PATCH_FILE" ]; then
        log_info "应用补丁 (--3way 合并)..."
        if git apply --3way "$PATCH_FILE"; then
            log_info "补丁应用成功"
        else
            log_error "补丁冲突！请手动解决。补丁文件: $PATCH_FILE"
            log_error "解决后执行: git commit -a -m 'sync upstream' && git push origin main -f"
            exit 1
        fi
    fi

    log_info "提交并推送到 origin/main..."
    git commit -a -m "sync: rebase onto upstream/main" || log_warn "无变更可提交"
    git push origin main --force-with-lease
}

# ---- 4. rebase 各 lite_* 分支 ----
rebase_lite_branches() {
    for branch in "${LITE_BRANCHES[@]}"; do
        log_info "--- 处理 $branch ---"

        if ! git rev-parse --verify "origin/$branch" &>/dev/null; then
            log_warn "跳过: 远程没有 $branch"
            continue
        fi

        git checkout "$branch"

        # 生成补丁（该分支相对 main）
        local patch_file="../${branch}.patch"
        log_info "生成 $branch 补丁..."
        git diff main...HEAD > "$patch_file"
        log_info "补丁: $patch_file ($(wc -l < "$patch_file") 行)"

        # 重置到 main
        log_info "重置 $branch 到 main..."
        git reset --hard main

        # 应用补丁
        if [ -s "$patch_file" ]; then
            log_info "应用补丁到 $branch..."
            if git apply --3way "$patch_file"; then
                log_info "$branch 补丁应用成功"
            else
                log_error "补丁冲突在 $branch！补丁文件: $patch_file"
                log_error "手动解决冲突后执行: git commit -a -m 'rebase ${branch}' && git push origin $branch -f"
                exit 1
            fi
        fi

        git commit -a -m "rebase: ${branch} onto updated main" || log_warn "$branch 无变更可提交"
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
save_and_switch
sync_main
rebase_lite_branches
restore_branch
log_info "======== 同步完成 ========"
log_info "补丁已保留，如需清理: rm ../*.patch"
