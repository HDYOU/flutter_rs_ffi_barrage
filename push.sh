#!/bin/bash
# ============================================================
# flutter_rs_ffi_barrage - Git 一键推送脚本
# ============================================================
# 使用方式:
#   ./push.sh
#   认证依赖 Git credential helper，不硬编码 token
# ============================================================

set -e

# 配置 Git 用户信息
git config user.name "HDYOU"
git config user.email "32186506+HDYOU@users.noreply.github.com"

REPO_URL="https://github.com/HDYOU/flutter_rs_ffi_barrage.git"

# 确保远程仓库配置正确（不含 token）
if git remote | grep -q "origin"; then
    git remote set-url origin "${REPO_URL}"
else
    git remote add origin "${REPO_URL}"
fi

echo "当前分支: $(git branch --show-current)"
echo "正在推送到 GitHub..."
git push -u origin "$(git branch --show-current)"

echo ""
echo "推送成功！"
echo "仓库地址: ${REPO_URL}"
