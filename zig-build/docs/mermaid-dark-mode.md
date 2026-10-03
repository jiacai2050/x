# mdBook 中 Mermaid 暗黑模式动态自适应技术方案

本文记录了在 mdBook 项目中实现 **Mermaid 架构流程图与暗黑主题（Navy / Coal / Ayu）极致融合** 的技术挑战、方案探索与最终的运行时色彩映射引擎实现。

---

## 1. 核心问题与根因排查

在 mdBook 文档中使用 Mermaid 绘制彩色架构流程图时，在暗黑模式下遇到了以下几类严重问题：

### 1.1 选择器不匹配（无法直接加载 CDN 脚本）
- mdBook 底层的 Markdown 渲染器（pulldown-cmark）将代码块 ` ```mermaid ` 编译为：
  ```html
  <pre><code class="language-mermaid">graph TD ...</code></pre>
  ```
- Mermaid 官方脚本的 `startOnLoad: true` 默认通过 `document.querySelectorAll(".mermaid")` 查找容器。
- **后果**：直接引入 CDN 脚本而不进行 DOM 适配时，Mermaid 根本找不到待渲染的目标，流程图会直接退化显示为原始文本代码块。

### 1.2 源码硬编码导致的“框内白底”
- 为了保持技术架构图的层级与功能分类语义（符合 Universal Color Rules），Markdown 源码末尾通常定义了显式样式：
  ```mermaid
  classDef default fill:#f8f9fa,stroke:#495057;
  style Phase1 fill:#fff0e6,stroke:#ff9900,stroke-width:2px;
  style B_Code fill:#f8f9fa,stroke:#495057,stroke-width:2px;
  ```
- 其中的 `#f8f9fa`（纯白/浅灰）、`#fff0e6`（浅橙）、`#cce5ff`（浅蓝）均为浅色色值。
- **后果**：无论使用何种版本的 Mermaid 库，Mermaid 都会忠实执行源码中的指令，将节点矩形填充为纯白色。在暗黑模式深色背景下，节点呈现为刺眼的白色方块。

### 1.3 白字落在白框上（对比度归零）
- 若向 Mermaid 传入 `theme: "dark"`，Mermaid 会将节点内部的文本标签（`.nodeLabel`、`text`）自动染为亮白色（`#f0f0f0`）。
- 结合上述的白框，导致**亮白色的文字被写在近乎纯白的浅色节点矩形上**，文字完全看不清。

### 1.4 暗黑主题漏判与动态切换失灵
- mdBook 拥有 3 种暗黑主题：`navy`、`coal` 和 `ayu`。早期脚本通常漏判了 `ayu`。
- mdBook 顶部工具栏切换主题时，仅通过 JavaScript 修改 `document.documentElement`（`<html>`）的 class，不刷新页面。Mermaid 渲染完的 SVG 属于静态 DOM，无法感知主题变化而自适应重绘。

---

## 2. 方案探索与对比

| 方案 | 做法 | 结果与局限 |
| :--- | :--- | :--- |
| **尝试一：独立白底卡片容器** | 为 `.mermaid` 容器添加白色卡片背景（`background: #fff; padding: 20px;`） | 保证了图表的高清对比度，但用户体验上在暗黑页面中会出现大面积白色卡片，不符合“原生暗色融入”的审美要求。 |
| **最终方案：按需 CDN 加载 + 运行时色彩映射引擎 + DOM 动态监听** | 仅在检测到图表代码块时按需注入 CDN 脚本，结合源码浅色 Hex 转深色映射与 `MutationObserver` 监听 | **完美解决**：无图页面 0 额外开销、免捆绑 3.3MB 冗余 JS、框内无白底、文字高亮清晰、支持全主题动态切换。 |

---

## 3. 最终架构与实现解析

### 3.1 运行时暗黑色彩映射引擎（`static/mermaid-init.js`）

在向 Mermaid 调度渲染前，先通过正则令牌匹配将浅色 Hex 色值映射到深度调优的暗黑调色板：

```javascript
// Mapping from light pastel colors to deep dark mode colors
const DARK_COLOR_MAP = {
    // 浅色底色 -> 对应暗黑深色底色（保持色彩语义）
    "#f8f9fa": "#1c2128", // 默认节点：转为 GitHub Dark 风格深灰
    "#ffffff": "#1c2128",
    "#cce5ff": "#13233a", // 蓝色节点：转为深海蓝
    "#e6f3ff": "#101c2e",
    "#fff0e6": "#261a12", // 橙色节点/子图：转为深琥珀橙
    "#e6ffe6": "#122416", // 绿色节点/子图：转为深森林绿
    "#fff3cd": "#262010", // 黄色节点：转为深金黄
    "#f8d7da": "#2d1417", // 红色节点：转为深红

    // 描边/边框 -> 提升亮度，使其在暗黑背景下清晰发光
    "#0066cc": "#58a6ff",
    "#009900": "#3fb950",
    "#495057": "#8b949e",
    "#dc3545": "#f85149"
};

// 使用单词边界确保精确匹配十六进制颜色，避免 #fff 误伤 #fff0e6 的子串替换 Bug
function transformToDarkTheme(source) {
    return source.replace(/#([0-9a-fA-F]{3,6})\b/g, (match) => {
        const lower = match.toLowerCase();
        return DARK_COLOR_MAP[lower] || match;
    });
}
```

### 3.2 源码缓存与动态重绘驱动

```javascript
// 1. 转换容器并缓存原始文本源码
function prepareContainers() {
    const blocks = document.querySelectorAll("pre code.language-mermaid, pre code.language-flowchart");
    blocks.forEach((block) => {
        const pre = block.parentElement;
        const container = document.createElement("div");
        container.className = "mermaid";
        container.dataset.mermaidSrc = block.textContent; // 缓存原始代码
        pre.parentNode.replaceChild(container, pre);
    });
}

// 2. 调度渲染：根据主题状态注入对应代码与主题配置
async function renderMermaid() {
    const isDark = document.documentElement.classList.contains("navy") ||
                   document.documentElement.classList.contains("coal") ||
                   document.documentElement.classList.contains("ayu");

    containers.forEach((container) => {
        container.removeAttribute("data-processed");
        const rawCode = container.dataset.mermaidSrc;
        container.textContent = isDark ? transformToDarkTheme(rawCode) : rawCode;
    });

    mermaid.initialize({
        startOnLoad: false,
        theme: isDark ? "dark" : "default",
        securityLevel: "loose"
    });

    await mermaid.run({ nodes: document.querySelectorAll(".mermaid") });
}

// 3. 监听 mdBook 主题切换
function setupThemeObserver() {
    let currentDarkState = isDarkTheme();
    const observer = new MutationObserver(() => {
        const newDarkState = isDarkTheme();
        if (newDarkState !== currentDarkState) {
            currentDarkState = newDarkState;
            renderMermaid();
        }
    });
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
}
```

### 3.3 CSS 高对比度细节润色（`static/custom.css`）

- **连线标签徽标化（Badge）**：给连线说明文字（`.edgeLabel`）添加 `rgba(22, 25, 35, 0.9)` 半透明深色药丸胶囊底色与亮白文字（`#e6edf3`），无论横穿深色页面还是子图内部均清晰可读。
- **高对比连线与箭头**：连线和箭头标记统一强化为高清晰度中性灰 `#8b949e`。
- **文字保底**：确保节点内部文字强制保持亮色高对比度。

### 3.4 交互增强：点击放大与平移查看（Lightbox 弹窗）

针对节点较多、字体较小、难以看清细节的架构大图，实现了纯原生自研的轻量 Lightbox 查看器：
- **悬浮提示**：鼠标移入 `.mermaid` 图表时，光标自动变为 `zoom-in` 并显现“🔍 点击放大”徽标。
- **全屏模态弹窗**：点击图表任意区域，全屏弹出半透明毛玻璃蒙层（Backdrop），将矢量 SVG 放大至全屏居中展示。
- **流畅交互操作**：
  - **鼠标滚轮**：平滑放大/缩小（0.4x ~ 6.0x）；
  - **拖拽平移**：按住鼠标左键可自由拖动平移查看超大图的任意局部；
  - **双击重置**：双击视口快速恢复默认比例居中；
  - **快捷关闭**：点击右上角关闭按钮（✕）、点击背景空白处或按下键盘 `Esc` 键均可关闭。
- **同构样式继承**：弹窗内的 SVG 容器同样挂载 `.mermaid` 类名，暗黑与明亮模式的全部对比度与色彩映射规则无缝复用。

---

## 4. 收益与效果验证

1. **暗黑模式下无任何白色方块**：所有节点由纯白（`#f8f9fa`）自动转为深灰（`#1c2128`），各功能分区依然清晰保有蓝、橙、绿、黄的深层色阶。
2. **文字极致清晰**：深色卡片背景搭配 Mermaid 原生亮白文字，对比度符合 WCAG AAA 标准。
3. **明亮模式原貌保留**：切回 `light` 或 `rust` 主题时，完全还原为原版清爽的浅色方案。
4. **单页切换零延迟**：mdBook 顶部切换主题时，流程图自动秒级响应重绘，无需刷新。
5. **按需 CDN 动态引入**：仅在当前页面存在 Mermaid 代码块时才动态注入 CDN 脚本，无图页面 0 额外网络与脚本开销，彻底剔除 3.3MB 本地巨石脚本。
6. **点击无级缩放体验**：支持任意复杂图表一键全屏放大查看，支持滚轮缩放与鼠标拖拽平移。
