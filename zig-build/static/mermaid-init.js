// Mermaid dynamic rendering for mdBook with on-demand CDN loading, dark mode adaptation & fullscreen zoom
(function () {
    let isRendering = false;
    let isScriptLoading = false;
    const scriptCallbacks = [];

    // Mapping from light pastel colors to deep dark mode colors
    const DARK_COLOR_MAP = {
        // Pastel fills -> Deep dark fills
        "#f8f9fa": "#1c2128",
        "#f9f9f9": "#1c2128",
        "#f0f0f0": "#1c2128",
        "#ffffff": "#1c2128",
        "#fff": "#1c2128",
        "#cce5ff": "#13233a",
        "#e6f3ff": "#101c2e",
        "#dae8fc": "#13233a",
        "#fff0e6": "#261a12",
        "#ffebcc": "#261a12",
        "#ffe6cc": "#261a12",
        "#e6ffe6": "#122416",
        "#ccffcc": "#122416",
        "#d1e7dd": "#122416",
        "#d5e8d4": "#122416",
        "#fff3cd": "#262010",
        "#fff2cc": "#262010",
        "#f8d7da": "#2d1417",
        "#f8cecc": "#2d1417",
        "#faa": "#2d1417",
        "#ffa": "#262010",
        "#ccc": "#30363d",

        // Borders / strokes -> High-contrast strokes for dark background
        "#0066cc": "#58a6ff",
        "#009900": "#3fb950",
        "#198754": "#3fb950",
        "#495057": "#8b949e",
        "#dc3545": "#f85149"
    };

    function isDarkTheme() {
        const cl = document.documentElement.classList;
        return cl.contains("navy") || cl.contains("coal") || cl.contains("ayu");
    }

    function transformToDarkTheme(source) {
        return source.replace(/#([0-9a-fA-F]{3,6})\b/g, (match) => {
            const lower = match.toLowerCase();
            return DARK_COLOR_MAP[lower] || match;
        });
    }

    // Convert code blocks to mermaid containers and preserve original diagram source
    function prepareContainers(blocks) {
        blocks.forEach((block) => {
            const pre = block.parentElement;
            if (!pre) return;
            const container = document.createElement("div");
            container.className = "mermaid";
            container.dataset.mermaidSrc = block.textContent;
            pre.parentNode.replaceChild(container, pre);
        });
    }

    // Load mermaid script dynamically on demand from CDN
    function loadMermaidScript(callback) {
        if (window.mermaid) {
            callback();
            return;
        }

        scriptCallbacks.push(callback);
        if (isScriptLoading) return;
        isScriptLoading = true;

        const script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js";
        script.onload = () => {
            isScriptLoading = false;
            while (scriptCallbacks.length > 0) {
                const cb = scriptCallbacks.shift();
                try {
                    cb();
                } catch (e) {
                    console.error("Error in mermaid script callback:", e);
                }
            }
        };
        script.onerror = (err) => {
            isScriptLoading = false;
            console.error("Failed to load Mermaid from CDN:", err);
        };
        document.head.appendChild(script);
    }

    async function renderMermaid() {
        if (typeof mermaid === "undefined" || isRendering) return;
        isRendering = true;

        try {
            const containers = document.querySelectorAll(".mermaid");
            if (containers.length === 0) return;

            const isDark = isDarkTheme();

            // Set up each container with appropriate light or dark diagram code
            containers.forEach((container) => {
                if (container.dataset.mermaidSrc) {
                    container.removeAttribute("data-processed");
                    const rawCode = container.dataset.mermaidSrc;
                    container.textContent = isDark ? transformToDarkTheme(rawCode) : rawCode;
                }
            });

            // Initialize Mermaid with matching theme
            mermaid.initialize({
                startOnLoad: false,
                theme: isDark ? "dark" : "default",
                securityLevel: "loose",
                flowchart: {
                    htmlLabels: true,
                    curve: "basis"
                }
            });

            // Run rendering
            await mermaid.run({
                nodes: document.querySelectorAll(".mermaid")
            });

            // Re-bind zoom events
            bindZoomEvents();
        } catch (err) {
            console.error("Mermaid rendering error:", err);
        } finally {
            isRendering = false;
        }
    }

    // Watch mdBook theme switches dynamically
    function setupThemeObserver() {
        let currentDarkState = isDarkTheme();
        const observer = new MutationObserver(() => {
            const newDarkState = isDarkTheme();
            if (newDarkState !== currentDarkState) {
                currentDarkState = newDarkState;
                renderMermaid();
            }
        });

        observer.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ["class"]
        });
    }

    // In-place Fullscreen Zoom Manager (No cloning, no lost SVGs, zero duplicate IDs)
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

        // Restore active SVG
        activeSvg.style.transform = "";

        // Remove toolbar & hint
        if (toolbarEl && toolbarEl.parentNode) {
            toolbarEl.parentNode.removeChild(toolbarEl);
        }
        if (hintEl && hintEl.parentNode) {
            hintEl.parentNode.removeChild(hintEl);
        }

        // Remove placeholder and restore container
        if (placeholder && placeholder.parentNode) {
            placeholder.parentNode.removeChild(placeholder);
        }
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

        // Create a layout placeholder so the page content doesn't jump
        const rect = container.getBoundingClientRect();
        placeholder = document.createElement("div");
        placeholder.style.height = `${rect.height}px`;
        placeholder.style.margin = getComputedStyle(container).margin;
        container.parentNode.insertBefore(placeholder, container);

        // Promote container to fullscreen
        container.classList.add("mermaid-fullscreen");
        document.body.style.overflow = "hidden";

        // Create toolbar
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

        // Create hint
        hintEl = document.createElement("div");
        hintEl.className = "mermaid-fs-hint";
        hintEl.textContent = "滚轮缩放 · 拖拽平移 · 双击重置 · ESC 或点击背景关闭";
        document.body.appendChild(hintEl);

        // Attach toolbar button events
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

        // Initialize scale
        resetSvgTransform();
    }

    // Global listeners for zoom & pan
    function setupGlobalInteractionListeners() {
        // Close on ESC
        document.addEventListener("keydown", (e) => {
            if (e.key === "Escape" && activeContainer) {
                closeFullscreen();
            }
        });

        // Wheel zoom when in fullscreen
        window.addEventListener("wheel", (e) => {
            if (!activeContainer) return;
            e.preventDefault();
            const factor = e.deltaY < 0 ? 1.15 : 0.87;
            zoomLevel = Math.min(Math.max(zoomLevel * factor, 0.4), 6.0);
            updateSvgTransform();
        }, { passive: false });

        // Drag to pan
        window.addEventListener("mousedown", (e) => {
            if (!activeContainer) return;
            // Ignore toolbar clicks
            if (e.target.closest(".mermaid-fs-toolbar")) return;

            // If user clicked directly on the fullscreen backdrop (outside SVG content)
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

        // Double click resets zoom
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
                if (activeContainer) return; // Already fullscreen
                // Don't trigger if user clicked an explicit link
                if (e.target.closest("a")) return;
                const svg = container.querySelector("svg");
                if (svg) {
                    openFullscreen(container, svg);
                }
            });
        });
    }

    function init() {
        const blocks = document.querySelectorAll("pre code.language-mermaid, pre code.language-flowchart");
        if (blocks.length === 0) return;

        prepareContainers(blocks);
        loadMermaidScript(() => {
            renderMermaid();
        });
        setupThemeObserver();
        setupGlobalInteractionListeners();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
