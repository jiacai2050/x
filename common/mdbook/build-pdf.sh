#!/usr/bin/env bash
# common/mdbook/build-pdf.sh
# 通用 mdbook PDF 构建脚本（支持直接在项目根目录运行，或以项目路径为参数运行）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 确定 mdbook 项目根目录
TARGET_DIR="${1:-.}"
if [ -f "$TARGET_DIR" ]; then
  # 如果第一个参数是输出文件（以 .pdf 结尾），则当前目录为根目录
  if [[ "$TARGET_DIR" == *.pdf ]]; then
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
DEFAULT_OUTPUT="$MDBOOK_BUILD_DIR/$PROJECT_NAME.pdf"
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

echo "===> [$BOOK_TITLE] 成功解析 ${#FILES[@]} 个章节，准备生成 Typst 源码..."

mkdir -p "$MDBOOK_BUILD_DIR/mermaid-images"
mkdir -p "$(dirname "$OUTPUT")"
TYP_OUTPUT="$MDBOOK_BUILD_DIR/$PROJECT_NAME.typ"

# 4. 生成动态注入的 header.typ
HEADER_FILE="$MDBOOK_BUILD_DIR/header.typ"
BUILD_DATE=$(date "+%Y-%m-%d %H:%M")

SUBTITLE=""
if [ -n "$BOOK_AUTHORS" ]; then
  SUBTITLE="作者：$BOOK_AUTHORS #h(1.5em) "
fi
SUBTITLE="${SUBTITLE}制作时间：$BUILD_DATE"

python3 -c "
with open('$SCRIPT_DIR/header.typ', 'r', encoding='utf-8') as f:
    content = f.read()
content = content.replace('BOOK_META_SUBTITLE_PLACEHOLDER', '''$SUBTITLE''')
with open('$HEADER_FILE', 'w', encoding='utf-8') as f:
    f.write(content)
"

# 语言转换，如 zh-CN 简化为 zh
DOC_LANG="${BOOK_LANG%%-*}"

# 5. Pandoc 转换
pandoc "${FILES[@]}" \
  --from=markdown+pipe_tables+backtick_code_blocks \
  --to=typst \
  --wrap=none \
  --standalone \
  --resource-path=".:$MDBOOK_SRC_DIR" \
  --lua-filter="$SCRIPT_DIR/mermaid-filter.lua" \
  --include-in-header="$HEADER_FILE" \
  --number-sections \
  -V mainfont="PingFang SC" \
  -V monofont="Menlo" \
  -V lang="$DOC_LANG" \
  -V paper="a4" \
  -V margin-x="2cm" \
  -V margin-y="2.5cm" \
  -o "$TYP_OUTPUT"

echo "===> Typst 源码生成完成: $TYP_OUTPUT"
echo "===> 正在编译 PDF: $OUTPUT ..."

# 6. 使用 Typst 编译为高保真 PDF
typst compile --root . "$TYP_OUTPUT" "$OUTPUT"

echo "===> PDF 构建成功: $PROJECT_DIR/$OUTPUT"
