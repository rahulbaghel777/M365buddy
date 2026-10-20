/* M365Buddy GitHub Discussions comments.
   Setup prerequisites:
   1. Enable Discussions for rahulbaghel777/M365buddy.
   2. Install https://github.com/apps/giscus for this repository.
   3. Create a Comments category using the Announcement format, then select it on https://giscus.app and paste its category ID below.
*/
(function () {
  "use strict";

  const config = {
    repo: "rahulbaghel777/M365buddy",
    repoId: "R_kgDOUOuk8Q",
    category: "Comments",
    // Replace after Discussions is enabled and the category is selected at giscus.app.
    categoryId: "GISCUS_CATEGORY_ID_PENDING",
    mapping: "pathname",
    strict: "0",
    reactionsEnabled: "1",
    emitMetadata: "0",
    inputPosition: "bottom",
    theme: "light",
    lang: "en"
  };

  const isConfigured = config.categoryId &&
    config.categoryId !== "GISCUS_CATEGORY_ID_PENDING" &&
    /^DIC_[A-Za-z0-9_]+$/.test(config.categoryId);

  const setupNotice = document.querySelector("[data-community-setup-pending]");
  if (setupNotice && isConfigured) setupNotice.hidden = true;

  document.querySelectorAll("[data-giscus-comments]").forEach(function (container) {
    const fallback = container.querySelector("[data-giscus-pending]");
    if (!isConfigured) {
      if (fallback) fallback.hidden = false;
      return;
    }

    if (container.dataset.giscusLoaded === "true") return;
    container.dataset.giscusLoaded = "true";
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
    script.onerror = function () {
      if (fallback) fallback.hidden = false;
      container.dataset.giscusLoaded = "false";
    };
    container.appendChild(script);
    if (fallback) fallback.hidden = true;
  });
})();
