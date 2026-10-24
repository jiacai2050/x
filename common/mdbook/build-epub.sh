#!/usr/bin/env bash
# common/mdbook/build-epub.sh
# 通用 mdbook EPUB 构建脚本（支持直接在项目根目录运行，或以项目路径为参数运行）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 确定 mdbook 项目根目录
TARGET_DIR="${1:-.}"
if [ -f "$TARGET_DIR" ]; then
  if [[ "$TARGET_DIR" == *.epub ]]; then
    CUSTOM_OUTPUT="$TARGET_DIR"
    PROJECT_DIR="."
  else
    PROJECT_DIR="$(dirname "$TARGET_DIR")"
    CUSTOM_OUTPUT=""
  fi
else
  PROJECT_DIR="$TARGET_DIR"
  CUSTOM_OUTPUT="${2:-}"
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
cd "$PROJECT_DIR"

if [ ! -f "book.toml" ]; then
  echo "错误: $PROJECT_DIR 下未找到 book.toml，请确认是否为 mdbook 项目根目录！"
  exit 1
fi

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

# 2. 从 book.toml 解析元数据
eval "$(python3 -c '
import tomllib, os, shlex

with open("book.toml", "rb") as f:
    cfg = tomllib.load(f)

book = cfg.get("book", {})
build = cfg.get("build", {})

title = book.get("title", os.path.basename(os.getcwd()))
authors = ", ".join(book.get("authors", []))
description = book.get("description", "")
language = book.get("language", "zh-CN")
src_dir = book.get("src", "src")
build_dir = build.get("build-dir", "book")

print(f"BOOK_TITLE={shlex.quote(title)}")
print(f"BOOK_AUTHORS={shlex.quote(authors)}")
print(f"BOOK_DESCRIPTION={shlex.quote(description)}")
print(f"BOOK_LANG={shlex.quote(language)}")
print(f"MDBOOK_SRC_DIR={shlex.quote(src_dir)}")
print(f"MDBOOK_BUILD_DIR={shlex.quote(build_dir)}")
')"

export MDBOOK_SRC_DIR
export MDBOOK_BUILD_DIR

PROJECT_NAME="$(basename "$PROJECT_DIR")"
DEFAULT_OUTPUT="$MDBOOK_BUILD_DIR/$PROJECT_NAME.epub"
OUTPUT="${CUSTOM_OUTPUT:-$DEFAULT_OUTPUT}"

# 3. 按 SUMMARY.md 目录顺序提取 Markdown 章节文件
SUMMARY_FILE="$MDBOOK_SRC_DIR/SUMMARY.md"
if [ ! -f "$SUMMARY_FILE" ]; then
  echo "错误: 未找到 $SUMMARY_FILE"
  exit 1
fi

FILES=()
while IFS= read -r line; do
  rel_path=$(echo "$line" | sed -n 's/.*(\([^)]*\.md\)).*/\1/p')
  if [ -n "$rel_path" ]; then
    full_path="$MDBOOK_SRC_DIR/$rel_path"
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

echo "===> [$BOOK_TITLE] 成功解析 ${#FILES[@]} 个章节，准备生成 EPUB: $OUTPUT"

mkdir -p "$MDBOOK_BUILD_DIR/mermaid-images"
mkdir -p "$(dirname "$OUTPUT")"

# 4. Pandoc 转换
# - 使用 Lua filter 自动嵌入高清 Mermaid 图像；
# - 不生成内嵌式正文 TOC（阅读器自带大纲导航）；
# - --epub-title-page=false 去除多余的单行标题扉页；
# - --css="epub.css" 解决 h1 page-break-before 导致章节间多出空白页的问题。
PANDOC_ARGS=(
  "${FILES[@]}"
  --from=markdown+pipe_tables+backtick_code_blocks
  --to=epub3
  --resource-path=".:$MDBOOK_SRC_DIR:$MDBOOK_BUILD_DIR"
  --lua-filter="$SCRIPT_DIR/mermaid-filter.lua"
  --metadata=title="$BOOK_TITLE"
  --metadata=date="$(date '+%Y-%m-%d')"
  --metadata=lang="$BOOK_LANG"
  --epub-title-page=false
  --css="$SCRIPT_DIR/epub.css"
  -o "$OUTPUT"
)

if [ -n "$BOOK_AUTHORS" ]; then
  PANDOC_ARGS+=(--metadata=author="$BOOK_AUTHORS")
fi

if [ -n "$BOOK_DESCRIPTION" ]; then
  PANDOC_ARGS+=(--metadata=description="$BOOK_DESCRIPTION")
fi

pandoc "${PANDOC_ARGS[@]}"

echo "===> EPUB 构建成功: $PROJECT_DIR/$OUTPUT"
