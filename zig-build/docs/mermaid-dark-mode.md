# mdBook 中 Mermaid 原生暗黑模式轻量工程方案

本文记录了在 mdBook 项目中实现 **Mermaid 架构流程图与暗黑主题（Navy / Coal / Ayu）零 CSS 纯原生融合** 的极简工程实践。

---

## 1. 核心设计原则：零外部 CSS 依赖

Mermaid 本身是一个高度自包含的矢量绘图引擎：
- **自包含样式**：每个生成的 SVG 自带内联 `<style>` 标签，定义其主题全部样式；
- **官方内置主题**：Mermaid 官方直接提供了 `theme: "default"`（浅色）和 `theme: "dark"`（深色）；
- **无需外部 CSS**：只要遵循最佳实践，**`book.toml` 中完全不需要引入 `additional-css`**。

---

## 2. 传统实践中的“白底”误区与正统解法

### 2.1 误区：在 Markdown 源码中硬编码浅色 `fill:#...`
此前在绘制彩色架构图时，常在末尾添加内联样式：
```mermaid
%% 反模式：写死了浅色填充
classDef core fill:#e6f3ff,stroke:#0066cc;
style SG_FrontEnd fill:#f8fbff,stroke:#0066cc;
```
由于内联 `style fill` 和 `classDef fill` 的优先级高于 Mermaid 的主题配置（`theme: "dark"`），Mermaid 在暗黑模式下依然忠实执行源码指令将矩形填白，产生刺眼白框。

### 2.2 正统解法：只声明边框描边（`stroke`），填充由主题自适应
```mermaid
%% 推荐做法：只通过描边表达功能分类，底色与文字交给主题自适应
classDef core stroke:#0066cc,stroke-width:2px;
classDef middle stroke:#ff9900,stroke-width:2px;
classDef mem stroke:#009900,stroke-width:2px;
style SG_FrontEnd stroke:#0066cc,stroke-width:2px;
```
- **明亮模式下**：Mermaid 自动填充默认浅色背景，搭配彩色边框；
- **暗黑模式下**：Mermaid 自动填充官方深灰色背景（`#1f2428`），搭配高亮发光的彩色边框；
- **文字与连线**：Mermaid 官方暗黑主题自动渲染浅色高对比文字与连线。

---

## 3. 架构实现：纯原生运行时（`static/mermaid-init.js`）

全站仅需一个几十行的轻量 JS 脚本：

```javascript
// Mermaid runtime initialization for mdBook with on-demand CDN loading & native theme adaptation
(function () {
    let isRendering = false;

    function isDarkTheme() {
        const cl = document.documentElement.classList;
        return cl.contains("navy") || cl.contains("coal") || cl.contains("ayu");
    }

    // 1. DOM 适配：将 <pre><code class="language-mermaid"> 转换为 <div class="mermaid">
    function prepareContainers() {
        const blocks = document.querySelectorAll("pre code.language-mermaid, pre code.language-flowchart");
        if (blocks.length === 0) return false;

        blocks.forEach((codeBlock) => {
            const pre = codeBlock.parentElement;
            if (!pre) return;
            const container = document.createElement("div");
            container.className = "mermaid";
            container.dataset.mermaidSrc = codeBlock.textContent;
            container.textContent = codeBlock.textContent;
            container.style.display = "flex";
            container.style.justifyContent = "center";
            container.style.margin = "24px 0";
            container.style.overflowX = "auto";
            pre.parentNode.replaceChild(container, pre);
        });
        return true;
    }

    // 2. 按需加载 CDN 脚本：仅有图页面发起请求
    function loadMermaidScript(callback) {
        if (window.mermaid) {
            callback();
            return;
        }

        const script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js";
        script.onload = () => callback();
        script.onerror = (err) => console.error("Failed to load Mermaid from CDN:", err);
        document.head.appendChild(script);
    }

    // 3. 原生主题渲染
    async function renderMermaid() {
        if (typeof mermaid === "undefined" || isRendering) return;
        isRendering = true;

        try {
            const containers = document.querySelectorAll(".mermaid");
            if (containers.length === 0) return;

            const isDark = isDarkTheme();

            containers.forEach((container) => {
                if (container.dataset.mermaidSrc) {
                    container.removeAttribute("data-processed");
                    container.textContent = container.dataset.mermaidSrc;
                }
            });

            mermaid.initialize({
                startOnLoad: false,
                securityLevel: "loose",
                theme: isDark ? "dark" : "default"
            });

            await mermaid.run({
                nodes: document.querySelectorAll(".mermaid")
            });
        } catch (err) {
            console.error("Mermaid rendering error:", err);
        } finally {
            isRendering = false;
        }
    }

    // 4. 监听 mdBook 顶栏主题切换
    function setupThemeObserver() {
        let currentDarkState = isDarkTheme();
        const observer = new MutationObserver(() => {
            const newDarkState = isDarkTheme();
            if (newDarkState !== currentDarkState) {
                currentDarkState = newDarkState;
                if (typeof mermaid !== "undefined") {
                    renderMermaid();
                }
            }
        });

        observer.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["class"]
        });
    }

    function init() {
        const hasBlocks = prepareContainers();
        if (!hasBlocks) return;

        loadMermaidScript(() => {
            renderMermaid();
            setupThemeObserver();
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
```

---

## 4. 收益

1. **零 CSS 依赖**：从 `book.toml` 中彻底移除 `additional-css`，全书无任何自定义 CSS 文件。
2. **零 JS 黑魔法**：不再使用任何正则修改源码颜色，100% 遵守 Mermaid 原生 API。
3. **按需轻量**：无流程图章节 0 脚本开销。
4. **两书共享规范**：`zig-build` 与 `zig-compiler` 通过软链接共享同一份极简架构。
5. **自包含交互缩放**：全屏 Lightbox 缩放与平移功能完整保留，其 UI 样式由 JS 动态自包含注入，兼得“零外部 CSS 文件”与“复杂图表交互缩放查看”的双重体验。
