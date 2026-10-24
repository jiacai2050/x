-- common/mdbook/mermaid-filter.lua
-- Pandoc Lua Filter: 将 mermaid 代码块调用本地 mmdc 转换为 3x 高清图片并嵌入文档

local system = pandoc.system
local sha1 = pandoc.sha1

-- 查找系统默认 Chrome 路径，供 mmdc / puppeteer 使用
local default_chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
local pptr_env = ""
if os.getenv("PUPPETEER_EXECUTABLE_PATH") == nil then
  local f = io.open(default_chrome, "r")
  if f then
    f:close()
    pptr_env = string.format("PUPPETEER_EXECUTABLE_PATH=%q ", default_chrome)
  end
end

-- 判断当前输出格式是否为 typst
local is_typst = (FORMAT == "typst")

local src_dir = os.getenv("MDBOOK_SRC_DIR") or "src"
local book_dir = os.getenv("MDBOOK_BUILD_DIR") or "book"

function CodeBlock(block)
  if block.classes:includes("mermaid") then
    local hash = sha1(block.text)
    local out_dir = book_dir .. "/mermaid-images"
    local local_file = out_dir .. "/" .. hash .. ".png"
    -- Typst 中以 / 开头的路径表示相对于 --root 的路径；EPUB 等其他格式使用相对路径
    local img_ref = is_typst and ("/" .. local_file) or local_file

    system.make_directory(out_dir, true)

    local f = io.open(local_file, "r")
    if not f then
      local mmd_path = out_dir .. "/" .. hash .. ".mmd"
      local out = io.open(mmd_path, "w")
      if out then
        out:write(block.text)
        out:close()
        -- 使用 -s 3 (3倍 Retina 缩放) 生成超清印刷级图片
        local cmd = string.format("%smmdc -i %q -o %q -s 3 -b transparent >/dev/null 2>&1", pptr_env, mmd_path, local_file)
        os.execute(cmd)
        os.remove(mmd_path)
      end
    else
      f:close()
    end

    return pandoc.Para({ pandoc.Image({}, img_ref) })
  end
end

function Image(img)
  -- 规范化相对图片路径
  if not img.src:match("^/") and not img.src:match("^https?://") then
    local candidate = src_dir .. "/" .. img.src
    if img.src == "cover.svg" or io.open(candidate, "r") then
      img.src = is_typst and ("/" .. candidate) or candidate
    end
  end
  return img
end
