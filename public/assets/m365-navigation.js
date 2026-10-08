/* =========================================================
   M365Buddy - Shared Navigation & Search Engine
   ========================================================= */

(function () {
    "use strict";

    /* =====================================================
       Helpers
       ===================================================== */

    function $(selector, parent) {
        return (parent || document).querySelector(selector);
    }

    function $$(selector, parent) {
        return Array.from(
            (parent || document).querySelectorAll(selector)
        );
    }

    function escapeHtml(value) {
        return String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
    }

    function normalize(value) {
        return String(value || "")
            .toLowerCase()
            .trim();
    }

    function currentPath() {
        return window.location.pathname
            .replace(/\/+$/, "")
            .toLowerCase();
    }

    /* =====================================================
       HEADER ACTIVE STATE
       ===================================================== */

    function initializeHeader() {
        const path = currentPath();

        $$(".m365-main-nav a").forEach(function (link) {
            const href = link.getAttribute("href");

            if (!href || href.startsWith("#")) {
                return;
            }

            try {
                const linkPath = new URL(
                    href,
                    window.location.origin
                ).pathname
                    .replace(/\/+$/, "")
                    .toLowerCase();

                if (
                    linkPath === path ||
                    (linkPath !== "/" && path.startsWith(linkPath))
                ) {
                    link.classList.add("active");
                }
            } catch (error) {
                // Ignore invalid navigation URLs.
            }
        });
    }

    /* =====================================================
       LEFT ARTICLE NAVIGATION
       ===================================================== */

    function initializeArticleNavigation() {
        const nav = $("[data-m365-article-nav]");

        if (!nav || typeof M365_INDEX === "undefined") {
            return;
        }

        const articles = M365_INDEX.filter(function (item) {
            return item.type === "Article";
        });

        nav.innerHTML = "";

        articles.forEach(function (article) {
            const link = document.createElement("a");

            link.href = article.url;
            link.textContent = article.title;

            const articlePath = new URL(
                article.url,
                window.location.origin
            ).pathname
                .replace(/\/+$/, "")
                .toLowerCase();

            if (articlePath === currentPath()) {
                link.classList.add("active");
            }

            nav.appendChild(link);
        });
    }

    /* =====================================================
       LEFT ARTICLE SEARCH
       ===================================================== */

    function initializeArticleListSearch() {
        const input = $("[data-m365-article-search]");

        if (!input) {
            return;
        }

        input.addEventListener("input", function () {
            const searchTerm = normalize(input.value);

            $$(".m365-article-nav a").forEach(function (link) {
                const title = normalize(link.textContent);

                link.style.display =
                    !searchTerm || title.includes(searchTerm)
                        ? ""
                        : "none";
            });
        });
    }

    /* =====================================================
       GLOBAL SEARCH
       ===================================================== */

    function initializeGlobalSearch() {
        const input = $("[data-m365-global-search]");
        const resultsContainer = $(
            "[data-m365-global-search-results]"
        );

        if (
            !input ||
            !resultsContainer ||
            typeof M365_INDEX === "undefined"
        ) {
            return;
        }

        function searchIndex(searchTerm) {
            const query = normalize(searchTerm);

            if (!query) {
                return [];
            }

            const words = query
                .split(/\s+/)
                .filter(Boolean);

            return M365_INDEX
                .map(function (item) {
                    const searchableText = normalize(
                        [
                            item.title,
                            item.type,
                            item.category,
                            item.description,
                            ...(item.keywords || [])
                        ].join(" ")
                    );

                    let score = 0;

                    words.forEach(function (word) {
                        if (normalize(item.title).includes(word)) {
                            score += 10;
                        }

                        if (normalize(item.category).includes(word)) {
                            score += 6;
                        }

                        if (normalize(item.type).includes(word)) {
                            score += 4;
                        }

                        if (
                            normalize(item.description).includes(word)
                        ) {
                            score += 3;
                        }

                        if (
                            (item.keywords || []).some(function (keyword) {
                                return normalize(keyword).includes(word);
                            })
                        ) {
                            score += 5;
                        }

                        if (searchableText.includes(word)) {
                            score += 1;
                        }
                    });

                    return {
                        item: item,
                        score: score
                    };
                })
                .filter(function (result) {
                    return result.score > 0;
                })
                .sort(function (a, b) {
                    return b.score - a.score;
                })
                .map(function (result) {
                    return result.item;
                });
        }

        function renderResults(results, query) {
            resultsContainer.innerHTML = "";

            if (!query) {
                resultsContainer.classList.remove("show");
                return;
            }

            if (!results.length) {
                resultsContainer.innerHTML =
                    '<div class="m365-search-result">' +
                    '<div class="m365-search-result-title">' +
                    "No results found" +
                    "</div>" +
                    '<div class="m365-search-result-description">' +
                    "Try a different Microsoft 365 topic, product, command or problem." +
                    "</div>" +
                    "</div>";

                resultsContainer.classList.add("show");
                return;
            }

            results.slice(0, 10).forEach(function (item) {
                const link = document.createElement("a");

                link.className = "m365-search-result";
                link.href = item.url;

                link.innerHTML =
                    '<div class="m365-search-result-title">' +
                    escapeHtml(item.title) +
                    "</div>" +

                    '<div class="m365-search-result-meta">' +
                    escapeHtml(item.type) +
                    " · " +
                    escapeHtml(item.category || "Microsoft 365") +
                    "</div>" +

                    '<div class="m365-search-result-description">' +
                    escapeHtml(item.description || "") +
                    "</div>";

                resultsContainer.appendChild(link);
            });

            resultsContainer.classList.add("show");
        }

        input.addEventListener("input", function () {
            const query = input.value;
            const results = searchIndex(query);

            renderResults(results, query);
        });

        input.addEventListener("keydown", function (event) {
            if (event.key === "Escape") {
                input.value = "";
                resultsContainer.classList.remove("show");
                input.blur();
            }
        });

        document.addEventListener("click", function (event) {
            if (
                !resultsContainer.contains(event.target) &&
                event.target !== input
            ) {
                resultsContainer.classList.remove("show");
            }
        });
    }

    /* =====================================================
       ARTICLE PAGE TOC
       ===================================================== */

    function initializePageNavigation() {
        const nav = $("[data-m365-page-nav]");
        const article = $("[data-m365-article]");

        if (!nav || !article) {
            return;
        }

        const headings = $$(
            "h2, h3",
            article
        );

        nav.innerHTML = "";

        headings.forEach(function (heading, index) {
            if (!heading.id) {
                const baseId =
                    normalize(heading.textContent)
                        .replace(/[^a-z0-9]+/g, "-")
                        .replace(/^-|-$/g, "");

                heading.id =
                    baseId ||
                    "section-" + (index + 1);
            }

            const link = document.createElement("a");

            link.href = "#" + heading.id;
            link.textContent = heading.textContent;

            if (heading.tagName.toLowerCase() === "h3") {
                link.style.paddingLeft = "12px";
                link.style.fontSize = "12px";
            }

            nav.appendChild(link);
        });
    }

    /* =====================================================
       CURRENT ARTICLE SEARCH
       ===================================================== */

    function initializeCurrentArticleSearch() {
        const input = $("[data-m365-current-search]");
        const article = $("[data-m365-article]");
        const count = $("[data-m365-search-count]");

        if (!input || !article) {
            return;
        }

        let searchTimer = null;

        function clearHighlights() {
            $$(".m365-highlight", article).forEach(function (highlight) {
                const parent = highlight.parentNode;

                if (!parent) {
                    return;
                }

                parent.replaceChild(
                    document.createTextNode(highlight.textContent),
                    highlight
                );

                parent.normalize();
            });
        }

        function highlightText(term) {
            clearHighlights();

            if (!term) {
                if (count) {
                    count.textContent = "";
                }

                return;
            }

            const normalizedTerm = normalize(term);

            if (!normalizedTerm) {
                return;
            }

            const walker = document.createTreeWalker(
                article,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode: function (node) {
                        const parent =
                            node.parentElement;

                        if (!parent) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        if (
                            parent.closest(
                                "script, style, pre, code, textarea, input, button, .m365-article-search"
                            )
                        ) {
                            return NodeFilter.FILTER_REJECT;
                        }

                        return normalize(node.nodeValue).includes(
                            normalizedTerm
                        )
                            ? NodeFilter.FILTER_ACCEPT
                            : NodeFilter.FILTER_REJECT;
                    }
                }
            );

            const textNodes = [];

            let node;

            while ((node = walker.nextNode())) {
                textNodes.push(node);
            }

            let matchCount = 0;

            textNodes.forEach(function (textNode) {
                const text = textNode.nodeValue;

                const lowerText = text.toLowerCase();

                let start = 0;
                let index;

                const fragment =
                    document.createDocumentFragment();

                while (
                    (index = lowerText.indexOf(
                        normalizedTerm,
                        start
                    )) !== -1
                ) {
                    fragment.appendChild(
                        document.createTextNode(
                            text.substring(start, index)
                        )
                    );

                    const span =
                        document.createElement("span");

                    span.className = "m365-highlight";

                    span.textContent = text.substring(
                        index,
                        index + normalizedTerm.length
                    );

                    fragment.appendChild(span);

                    start =
                        index + normalizedTerm.length;

                    matchCount++;
                }

                fragment.appendChild(
                    document.createTextNode(
                        text.substring(start)
                    )
                );

                textNode.parentNode.replaceChild(
                    fragment,
                    textNode
                );
            });

            if (count) {
                count.textContent =
                    matchCount === 1
                        ? "1 match found"
                        : matchCount + " matches found";
            }

            const firstMatch =
                $(".m365-highlight", article);

            if (firstMatch) {
                firstMatch.scrollIntoView({
                    behavior: "smooth",
                    block: "center"
                });
            }
        }

        input.addEventListener("input", function () {
            clearTimeout(searchTimer);

            searchTimer = setTimeout(function () {
                highlightText(input.value);
            }, 120);
        });

        input.addEventListener("keydown", function (event) {
            if (event.key === "Escape") {
                input.value = "";
                highlightText("");
                input.blur();
            }
        });
    }

    /* =====================================================
       INITIALIZE EVERYTHING
       ===================================================== */

    function initializeM365Buddy() {
        initializeHeader();
        initializeArticleNavigation();
        initializeArticleListSearch();
        initializeGlobalSearch();
        initializePageNavigation();
        initializeCurrentArticleSearch();
    }

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            initializeM365Buddy
        );
    } else {
        initializeM365Buddy();
    }

})();
