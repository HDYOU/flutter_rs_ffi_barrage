#!/bin/bash
# ============================================================
# flutter_rs_ffi_barrage - Git 一键推送脚本
# ============================================================
# 使用方式:
#   export GITHUB_TOKEN="your_token_here"
#   ./push.sh
# ============================================================

set -e

# 配置 Git 用户信息
git config user.name "HDYOU"
git config user.email "32186506+HDYOU@users.noreply.github.com"

# 从环境变量读取 Token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ 错误: 请先设置 GITHUB_TOKEN 环境变量"
    echo "   export GITHUB_TOKEN=\"your_token_here\""
    exit 1
fi

REPO_URL="https://github.com/HDYOU/flutter_rs_ffi_barrage.git"
AUTH_URL="https://HDYOU:${GITHUB_TOKEN}@github.com/HDYOU/flutter_rs_ffi_barrage.git"

# 检查是否已添加远程仓库
if git remote | grep -q "origin"; then
    git remote set-url origin "${AUTH_URL}"
else
    git remote add origin "${AUTH_URL}"
fi

echo "📦 当前分支: $(git branch --show-current)"
echo "🚀 正在推送到 GitHub..."
git push -u origin "$(git branch --show-current)"

# 推送完成后重置为公开 URL
git remote set-url origin "${REPO_URL}"

echo ""
echo "✅ 推送成功！"
echo "🌐 仓库地址: ${REPO_URL}"
