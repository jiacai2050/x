// Mermaid runtime initialization for mdBook with on-demand CDN loading & self-contained fullscreen zoom
(function () {
    let isRendering = false;

    function isDarkTheme() {
        const cl = document.documentElement.classList;
        return cl.contains("navy") || cl.contains("coal") || cl.contains("ayu");
    }

    // Inject self-contained styles for the interactive zoom & lightbox viewer (no external CSS needed)
    function injectViewerStyles() {
        if (document.getElementById("mermaid-viewer-styles")) return;
        const style = document.createElement("style");
        style.id = "mermaid-viewer-styles";
        style.textContent = `
            .mermaid {
                position: relative;
                display: flex;
                justify-content: center;
                margin: 24px 0;
                overflow-x: auto;
                cursor: zoom-in;
                border-radius: 8px;
                transition: background-color 0.2s ease;
            }
            .mermaid:hover {
                background-color: rgba(127, 127, 127, 0.06);
            }
            .mermaid::after {
                content: "🔍 点击放大";
                position: absolute;
                top: 8px;
                right: 12px;
                background: rgba(22, 27, 34, 0.85);
                color: #e6edf3;
                font-size: 11px;
                padding: 3px 8px;
                border-radius: 4px;
                border: 1px solid rgba(255, 255, 255, 0.15);
                opacity: 0;
                pointer-events: none;
                transition: opacity 0.2s ease, transform 0.2s ease;
                transform: translateY(-2px);
                z-index: 5;
            }
            .mermaid:hover::after {
                opacity: 1;
                transform: translateY(0);
            }
            .mermaid svg {
                max-width: 100%;
                height: auto;
            }
            .mermaid.mermaid-fullscreen {
                position: fixed !important;
                top: 0 !important;
                left: 0 !important;
                width: 100vw !important;
                height: 100vh !important;
                max-width: 100vw !important;
                margin: 0 !important;
                padding: 0 !important;
                z-index: 999999 !important;
                background-color: rgba(10, 12, 16, 0.92) !important;
                backdrop-filter: blur(8px) !important;
                -webkit-backdrop-filter: blur(8px) !important;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
                cursor: grab !important;
                overflow: hidden !important;
            }
            .mermaid.mermaid-fullscreen::after {
                display: none !important;
            }
            .mermaid.mermaid-fullscreen.dragging {
                cursor: grabbing !important;
            }
            .mermaid.mermaid-fullscreen svg {
                max-width: 90vw !important;
                max-height: 86vh !important;
                width: 100% !important;
                height: 100% !important;
                object-fit: contain !important;
                transform-origin: center center !important;
                filter: drop-shadow(0 8px 32px rgba(0, 0, 0, 0.6)) !important;
                user-select: none !important;
            }
            .mermaid-fs-toolbar {
                position: fixed;
                top: 16px;
                right: 20px;
                display: flex;
                gap: 8px;
                z-index: 1000000;
                background: rgba(22, 27, 34, 0.92);
                padding: 6px 10px;
                border-radius: 8px;
                border: 1px solid rgba(255, 255, 255, 0.15);
                box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
            }
            .mermaid-fs-btn {
                background: transparent;
                color: #e6edf3;
                border: none;
                cursor: pointer;
                padding: 6px;
                border-radius: 6px;
                display: flex;
                align-items: center;
                justify-content: center;
                transition: background-color 0.15s ease, color 0.15s ease;
            }
            .mermaid-fs-btn:hover {
                background-color: rgba(255, 255, 255, 0.15);
                color: #ffffff;
            }
            .mermaid-fs-close:hover {
                background-color: rgba(248, 81, 73, 0.3);
                color: #f85149;
            }
            .mermaid-fs-hint {
                position: fixed;
                bottom: 16px;
                left: 50%;
                transform: translateX(-50%);
                background: rgba(22, 27, 34, 0.85);
                color: #8b949e;
                font-size: 13px;
                padding: 6px 16px;
                border-radius: 20px;
                border: 1px solid rgba(255, 255, 255, 0.1);
                pointer-events: none;
                z-index: 1000000;
            }
        `;
        document.head.appendChild(style);
    }

    // Convert mdBook code blocks (<pre><code class="language-mermaid">) to Mermaid containers (<div class="mermaid">)
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
            pre.parentNode.replaceChild(container, pre);
        });
        return true;
    }

    // Load mermaid script dynamically on demand from CDN
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

    async function renderMermaid() {
        if (typeof mermaid === "undefined" || isRendering) return;
        isRendering = true;

        try {
            const containers = document.querySelectorAll(".mermaid");
            if (containers.length === 0) return;

            const isDark = isDarkTheme();

            // Restore original diagram code for clean re-rendering on theme switch
            containers.forEach((container) => {
                if (container.dataset.mermaidSrc) {
                    container.removeAttribute("data-processed");
                    container.textContent = container.dataset.mermaidSrc;
                }
            });

            // Initialize Mermaid with native theme matching mdBook
            mermaid.initialize({
                startOnLoad: false,
                securityLevel: "loose",
                theme: isDark ? "dark" : "default"
            });

            // Render all mermaid containers
            await mermaid.run({
                nodes: document.querySelectorAll(".mermaid")
            });

            bindZoomEvents();
        } catch (err) {
            console.error("Mermaid rendering error:", err);
        } finally {
            isRendering = false;
        }
    }

    // Watch mdBook theme switches dynamically without page reload
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

    // In-place Fullscreen Zoom Manager
    let activeContainer = null;
    let activeSvg = null;
    let placeholder = null;
    let toolbarEl = null;
    let hintEl = null;
    let zoomLevel = 1.0;
    let panX = 0;
    let panY = 0;
    let isDragging = false;
    let startX = 0;
    let startY = 0;

    function updateSvgTransform() {
        if (!activeSvg) return;
        activeSvg.style.transform = `translate(${panX}px, ${panY}px) scale(${zoomLevel})`;
    }

    function resetSvgTransform() {
        zoomLevel = 1.0;
        panX = 0;
        panY = 0;
        updateSvgTransform();
    }

    function closeFullscreen() {
        if (!activeContainer || !activeSvg) return;

        activeSvg.style.transform = "";

        if (toolbarEl && toolbarEl.parentNode) toolbarEl.parentNode.removeChild(toolbarEl);
        if (hintEl && hintEl.parentNode) hintEl.parentNode.removeChild(hintEl);
        if (placeholder && placeholder.parentNode) placeholder.parentNode.removeChild(placeholder);

        activeContainer.classList.remove("mermaid-fullscreen", "dragging");
        document.body.style.overflow = "";

        activeContainer = null;
        activeSvg = null;
        placeholder = null;
        toolbarEl = null;
        hintEl = null;
    }

    function openFullscreen(container, svg) {
        if (activeContainer) closeFullscreen();

        activeContainer = container;
        activeSvg = svg;

        const rect = container.getBoundingClientRect();
        placeholder = document.createElement("div");
        placeholder.style.height = `${rect.height}px`;
        placeholder.style.margin = getComputedStyle(container).margin;
        container.parentNode.insertBefore(placeholder, container);

        container.classList.add("mermaid-fullscreen");
        document.body.style.overflow = "hidden";

        toolbarEl = document.createElement("div");
        toolbarEl.className = "mermaid-fs-toolbar";
        toolbarEl.innerHTML = `
            <button class="mermaid-fs-btn" id="fs-btn-in" title="放大 (Zoom In)">
                <svg viewBox="0 0 24 24" width="20" height="20"><path fill="currentColor" d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/></svg>
            </button>
            <button class="mermaid-fs-btn" id="fs-btn-out" title="缩小 (Zoom Out)">
                <svg viewBox="0 0 24 24" width="20" height="20"><path fill="currentColor" d="M19 13H5v-2h14v2z"/></svg>
            </button>
            <button class="mermaid-fs-btn" id="fs-btn-reset" title="重置大小 (Reset)">
                <svg viewBox="0 0 24 24" width="18" height="18"><path fill="currentColor" d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/></svg>
            </button>
            <button class="mermaid-fs-btn mermaid-fs-close" id="fs-btn-close" title="退出全屏 (Esc)">
                <svg viewBox="0 0 24 24" width="20" height="20"><path fill="currentColor" d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
            </button>
        `;
        document.body.appendChild(toolbarEl);

        hintEl = document.createElement("div");
        hintEl.className = "mermaid-fs-hint";
        hintEl.textContent = "滚轮缩放 · 拖拽平移 · 双击重置 · ESC 或点击背景关闭";
        document.body.appendChild(hintEl);

        toolbarEl.querySelector("#fs-btn-in").addEventListener("click", (e) => {
            e.stopPropagation();
            zoomLevel = Math.min(zoomLevel * 1.25, 6.0);
            updateSvgTransform();
        });
        toolbarEl.querySelector("#fs-btn-out").addEventListener("click", (e) => {
            e.stopPropagation();
            zoomLevel = Math.max(zoomLevel / 1.25, 0.4);
            updateSvgTransform();
        });
        toolbarEl.querySelector("#fs-btn-reset").addEventListener("click", (e) => {
            e.stopPropagation();
            resetSvgTransform();
        });
        toolbarEl.querySelector("#fs-btn-close").addEventListener("click", (e) => {
            e.stopPropagation();
            closeFullscreen();
        });

        resetSvgTransform();
    }

    function setupGlobalInteractionListeners() {
        document.addEventListener("keydown", (e) => {
            if (e.key === "Escape" && activeContainer) closeFullscreen();
        });

        window.addEventListener("wheel", (e) => {
            if (!activeContainer) return;
            e.preventDefault();
            const factor = e.deltaY < 0 ? 1.15 : 0.87;
            zoomLevel = Math.min(Math.max(zoomLevel * factor, 0.4), 6.0);
            updateSvgTransform();
        }, { passive: false });

        window.addEventListener("mousedown", (e) => {
            if (!activeContainer) return;
            if (e.target.closest(".mermaid-fs-toolbar")) return;
            if (e.target === activeContainer) {
                closeFullscreen();
                return;
            }
            isDragging = true;
            activeContainer.classList.add("dragging");
            startX = e.clientX - panX;
            startY = e.clientY - panY;
        });

        window.addEventListener("mousemove", (e) => {
            if (!activeContainer || !isDragging) return;
            panX = e.clientX - startX;
            panY = e.clientY - startY;
            updateSvgTransform();
        });

        window.addEventListener("mouseup", () => {
            if (!activeContainer) return;
            isDragging = false;
            activeContainer.classList.remove("dragging");
        });

        window.addEventListener("dblclick", (e) => {
            if (!activeContainer) return;
            if (e.target.closest(".mermaid-fs-toolbar")) return;
            resetSvgTransform();
        });
    }

    function bindZoomEvents() {
        document.querySelectorAll(".mermaid").forEach((container) => {
            if (container.dataset.zoomBound) return;
            container.dataset.zoomBound = "true";
            container.addEventListener("click", (e) => {
                if (activeContainer) return;
                if (e.target.closest("a")) return;
                const svg = container.querySelector("svg");
                if (svg) openFullscreen(container, svg);
            });
        });
    }

    function init() {
        const hasBlocks = prepareContainers();
        if (!hasBlocks) return;

        injectViewerStyles();
        loadMermaidScript(() => {
            renderMermaid();
            setupThemeObserver();
        });
        setupGlobalInteractionListeners();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
