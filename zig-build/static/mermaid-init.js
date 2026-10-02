// Mermaid dynamic rendering for mdBook
(function () {
    function renderMermaid() {
        const blocks = document.querySelectorAll("pre code.language-mermaid, pre code.language-flowchart");
        blocks.forEach((block) => {
            const pre = block.parentElement;
            const container = document.createElement("div");
            container.className = "mermaid";
            container.textContent = block.textContent;
            pre.parentNode.replaceChild(container, pre);
        });

        if (typeof mermaid !== "undefined") {
            mermaid.initialize({
                startOnLoad: false,
                theme: document.documentElement.classList.contains("navy") || document.documentElement.classList.contains("coal") ? "dark" : "default",
                securityLevel: "loose"
            });
            mermaid.run({
                nodes: document.querySelectorAll(".mermaid")
            });
        }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", renderMermaid);
    } else {
        renderMermaid();
    }
})();
