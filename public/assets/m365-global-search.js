/* M365Buddy shared header search. Requires /assets/m365-search-index.js. */
(function () {
  "use strict";
  function escapeHtml(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
      return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c];
    });
  }
  function init() {
    document.querySelectorAll("[data-m365-search]").forEach(function (input) {
      if (input.dataset.m365SearchReady === "true") return;
      input.dataset.m365SearchReady = "true";
      var wrap = input.closest(".m365-search, .m365-header-search, .global-search") || input.parentElement;
      if (!wrap) return;
      var box = wrap.querySelector(".m365-results, .global-results");
      if (!box) {
        box = document.createElement("div");
        box.className = "m365-results";
        box.setAttribute("role", "listbox");
        wrap.appendChild(box);
      }
      function render() {
        var query = input.value.trim();
        if (!query) {
          box.classList.remove("show");
          box.innerHTML = "";
          return;
        }
        var api = window.M365BuddySearch;
        var items = api && typeof api.search === "function" ? api.search(query).slice(0, 7) : [];
        box.innerHTML = items.length ? items.map(function (item) {
          return '<a class="m365-result" role="option" href="' + escapeHtml(item.url) + '">' +
            '<span style="min-width:0"><span class="m365-result-title">' + escapeHtml(item.title) + '</span>' +
            '<span class="m365-result-desc">' + escapeHtml(item.description || item.category || "") + '</span></span>' +
            '<span class="m365-result-type">' + escapeHtml(item.type || "Result") + '</span></a>';
        }).join("") : '<div class="m365-result-empty">No matching articles or scripts. Try SharePoint, PowerShell, Entra ID, storage or automation.</div>';
        box.classList.add("show");
      }
      input.addEventListener("input", render);
      input.addEventListener("focus", render);
      input.addEventListener("keydown", function (event) {
        if (event.key === "Enter" && input.value.trim()) {
          event.preventDefault();
          window.location.href = "/search.html?q=" + encodeURIComponent(input.value.trim());
        } else if (event.key === "Escape") {
          input.value = "";
          render();
          box.classList.remove("show");
        }
      });
      document.addEventListener("click", function (event) {
        if (!wrap.contains(event.target)) box.classList.remove("show");
      });
    });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();