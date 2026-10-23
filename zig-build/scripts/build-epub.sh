#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT="${1:-book/zig-build.epub}"

# 1. 检查必要工具依赖（EPUB 由 pandoc 原生打包，无需 typst）
MISSING_TOOLS=()
for tool in pandoc mmdc; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
  echo "错误: 缺少以下工具依赖: ${MISSING_TOOLS[*]}"
  echo "请先安装所需依赖:"
  for tool in "${MISSING_TOOLS[@]}"; do
    case "$tool" in
      pandoc)
        echo "  - pandoc: brew install pandoc"
        ;;
      mmdc)
        echo "  - mmdc:   npm install -g @mermaid-js/mermaid-cli"
        ;;
    esac
  done
  exit 1
fi

# 若未显式设置 PUPPETEER_EXECUTABLE_PATH，优先适配 macOS 上的 Google Chrome
if [ -z "${PUPPETEER_EXECUTABLE_PATH:-}" ]; then
  MAC_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if [ -f "$MAC_CHROME" ]; then
    export PUPPETEER_EXECUTABLE_PATH="$MAC_CHROME"
  fi
fi

# 2. 按 src/SUMMARY.md 目录顺序提取 Markdown 章节文件
SUMMARY_FILE="src/SUMMARY.md"
if [ ! -f "$SUMMARY_FILE" ]; then
  echo "错误: 未找到 $SUMMARY_FILE"
  exit 1
fi

FILES=()
while IFS= read -r line; do
  rel_path=$(echo "$line" | sed -n 's/.*(\([^)]*\.md\)).*/\1/p')
  if [ -n "$rel_path" ]; then
    full_path="src/$rel_path"
    if [ -f "$full_path" ]; then
      FILES+=("$full_path")
    else
      echo "警告: 跳过不存在的文件: $full_path"
    fi
  fi
done < "$SUMMARY_FILE"

if [ ${#FILES[@]} -eq 0 ]; then
  echo "错误: 未解析到任何章节文件！"
  exit 1
fi

echo "===> 成功解析 ${#FILES[@]} 个章节，准备生成 EPUB: $OUTPUT"

mkdir -p book/mermaid-images
mkdir -p "$(dirname "$OUTPUT")"

# 3. Pandoc 转换:
# - 使用 Lua filter 自动嵌入高清 Mermaid 图像；
# - 不生成内嵌式正文 TOC（阅读器自带大纲导航）；
# - --epub-title-page=false 去除多余的单行标题扉页；
# - --css="scripts/epub.css" 解决 h1 page-break-before 导致章节间多出空白页的问题。
pandoc "${FILES[@]}" \
  --from=markdown+pipe_tables+backtick_code_blocks \
  --to=epub3 \
  --resource-path=".:src:book" \
  --lua-filter="scripts/mermaid-filter.lua" \
  --metadata=title="Zig 构建系统指南" \
  --metadata=author="jiacai2050" \
  --metadata=date="$(date '+%Y-%m-%d')" \
  --metadata=lang="zh-CN" \
  --metadata=description="Zig 构建系统指南：来龙去脉、核心概念、API 实战与底层运行机制" \
  --epub-title-page=false \
  --css="scripts/epub.css" \
  -o "$OUTPUT"

echo "===> EPUB 构建成功: $ROOT_DIR/$OUTPUT"
