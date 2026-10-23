#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT="${1:-book/zig-build.pdf}"

# 1. 检查必要工具依赖
MISSING_TOOLS=()
for tool in pandoc mmdc typst; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
  echo "错误: 缺少以下工具依赖: ${MISSING_TOOLS[*]}"
  echo "请先安装所需依赖:"
  for tool in "${MISSING_TOOLS[@]}"; do
    case "$tool" in
      typst)
        echo "  - typst:  brew install typst"
        ;;
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

echo "===> 成功解析 ${#FILES[@]} 个章节，准备生成 Typst 源码..."

mkdir -p book/mermaid-images
mkdir -p "$(dirname "$OUTPUT")"
TYP_OUTPUT="book/zig-build.typ"

# 动态注入制作时间至首页标题下方
HEADER_FILE="book/header.typ"
BUILD_DATE=$(date "+%Y-%m-%d %H:%M")
sed "s|BUILD_DATE_PLACEHOLDER|$BUILD_DATE|g" scripts/header.typ > "$HEADER_FILE"

# 3. Pandoc 转换: 使用 Lua filter 自动转换 Mermaid 图表为高清图像并输出 Typst 格式
# 注意: --wrap=none 避免软折行在行首出现 '/' 等字符与 Typst 列表语法产生冲突
pandoc "${FILES[@]}" \
  --from=markdown+pipe_tables+backtick_code_blocks \
  --to=typst \
  --wrap=none \
  --standalone \
  --resource-path=".:src" \
  --lua-filter="scripts/mermaid-filter.lua" \
  --include-in-header="$HEADER_FILE" \
  --number-sections \
  -V mainfont="PingFang SC" \
  -V monofont="Menlo" \
  -V lang="zh" \
  -V paper="a4" \
  -V margin-x="2cm" \
  -V margin-y="2.5cm" \
  -o "$TYP_OUTPUT"

echo "===> Typst 源码生成完成: $TYP_OUTPUT"
echo "===> 正在编译 PDF: $OUTPUT ..."

# 4. 使用 Typst 编译为高保真 PDF
typst compile --root . "$TYP_OUTPUT" "$OUTPUT"

echo "===> PDF 构建成功: $ROOT_DIR/$OUTPUT"
