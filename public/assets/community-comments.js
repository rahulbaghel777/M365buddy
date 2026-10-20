/* M365Buddy GitHub Discussions comments.
   One-time setup: see /COMMUNITY_COMMENTS_SETUP.md.
*/
(function () {
  "use strict";

  const config = {
    repo: "rahulbaghel777/M365buddy",
    repoId: "R_kgDOUOuk8Q",
    category: "Comments",
    // Replace with the DIC_... category ID from https://giscus.app after setup.
    categoryId: "GISCUS_CATEGORY_ID_PENDING",
    mapping: "pathname",
    strict: "0",
    reactionsEnabled: "1",
    emitMetadata: "0",
    inputPosition: "bottom",
    theme: "light",
    lang: "en"
  };

  const isConfigured = Boolean(
    config.categoryId &&
    config.categoryId !== "GISCUS_CATEGORY_ID_PENDING" &&
    /^DIC_[A-Za-z0-9_]+$/.test(config.categoryId)
  );

  const setupNotice = document.querySelector("[data-community-setup-pending]");
  if (setupNotice && isConfigured) setupNotice.hidden = true;

  document.querySelectorAll("[data-community-discussions-link]").forEach(function (link) {
    if (isConfigured) {
      if (link.dataset.discussionsHref) link.href = link.dataset.discussionsHref;
      link.removeAttribute("aria-disabled");
      link.removeAttribute("tabindex");
      link.classList.remove("is-disabled");
    } else {
      if (!link.dataset.discussionsHref) link.dataset.discussionsHref = link.href;
      link.href = "#community-discussion-status";
      link.setAttribute("aria-disabled", "true");
      link.setAttribute("tabindex", "-1");
      link.classList.add("is-disabled");
    }
  });

  function showLoadFailure(container, fallback) {
    container.dataset.giscusLoaded = "false";
    if (!fallback) return;

    fallback.hidden = false;
    const heading = fallback.querySelector("strong");
    const message = fallback.querySelector("p");

    if (heading) heading.textContent = "The GitHub discussion did not load";
    if (message) {
      message.textContent =
        "The embedded comments did not finish loading. Refresh the page, or use GitHub Issues below to report an issue or ask a question.";
    }
  }

  document.querySelectorAll("[data-giscus-comments]").forEach(function (container) {
    const fallback = container.querySelector("[data-giscus-pending]");

    if (!isConfigured) {
      if (fallback) fallback.hidden = false;
      return;
    }

    if (
      container.dataset.giscusLoaded === "true" ||
      container.dataset.giscusLoaded === "loading"
    ) return;

    container.dataset.giscusLoaded = "loading";

    let observer = null;
    let timeoutId = null;
    let ready = false;
    let scriptFailed = false;

    function cleanup() {
      if (observer) {
        observer.disconnect();
        observer = null;
      }
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId);
        timeoutId = null;
      }
    }

    function markReady() {
      if (ready || scriptFailed) return;
      ready = true;
      cleanup();
      container.dataset.giscusLoaded = "true";
      if (fallback) fallback.hidden = true;
    }

    function showFailure() {
      if (ready || scriptFailed) return;
      scriptFailed = true;
      cleanup();
      showLoadFailure(container, fallback);
    }

    function watchForFrame() {
      const frame = container.querySelector("iframe.giscus-frame");
      if (!frame || frame.dataset.m365CommentsObserved === "true") return;

      frame.dataset.m365CommentsObserved = "true";
      frame.addEventListener("load", markReady, { once: true });
      frame.addEventListener("error", showFailure, { once: true });
    }

    const script = document.createElement("script");
    script.src = "https://giscus.app/client.js";
    script.async = true;
    script.crossOrigin = "anonymous";
    script.setAttribute("data-repo", config.repo);
    script.setAttribute("data-repo-id", config.repoId);
    script.setAttribute("data-category", config.category);
    script.setAttribute("data-category-id", config.categoryId);
    script.setAttribute("data-mapping", config.mapping);
    script.setAttribute("data-strict", config.strict);
    script.setAttribute("data-reactions-enabled", config.reactionsEnabled);
    script.setAttribute("data-emit-metadata", config.emitMetadata);
    script.setAttribute("data-input-position", config.inputPosition);
    script.setAttribute("data-theme", config.theme);
    script.setAttribute("data-lang", config.lang);

    observer = new MutationObserver(watchForFrame);
    observer.observe(container, { childList: true, subtree: true });
    script.addEventListener("load", watchForFrame, { once: true });
    script.addEventListener("error", showFailure, { once: true });

    // Keep the fallback visible if the widget never creates/loads its iframe.
    // The observer remains active after timeout so a slow but successful load can recover.
    timeoutId = window.setTimeout(function () {
      if (ready || scriptFailed) return;
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId);
        timeoutId = null;
      }
      showLoadFailure(container, fallback);
    }, 20000);

    container.appendChild(script);
  });
})();
