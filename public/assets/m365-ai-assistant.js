(function () {
  "use strict";

  const form = document.getElementById("ask-form");
  const input = document.getElementById("question");
  const send = document.getElementById("send");
  const messages = document.getElementById("messages");
  const reset = document.getElementById("reset");
  if (!form || !input || !send || !messages) return;

  let history = [];
  let busy = false;

  function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, function (char) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char];
    });
  }

  function renderMarkdown(value) {
    return String(value ?? "").split(/(```[a-zA-Z0-9_-]*\n[\s\S]*?\`\`\`)/g).map(function (part) {
      if (part.startsWith("```")) {
        const code = part.replace(/^```[a-zA-Z0-9_-]*\n?/, "").replace(/\`\`\`$/, "");
        return "<pre class=\"assistant-code\"><code>" + escapeHtml(code) + "</code></pre>";
      }
      let safe = escapeHtml(part);
      safe = safe.replace(/\[([^\]]+)\]\((https:\/\/[^\s)]+|\/(?!\/)[^\s)]+)\)/g, function (_, label, href) {
        const external = href.startsWith("https://");
        return '<a href="' + href + '"' + (external ? ' target="_blank" rel="noopener noreferrer"' : "") + ">" + label + "</a>";
      });
      safe = safe.replace(/`([^`]+)`/g, "<code>$1</code>");
      safe = safe.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
      return safe.replace(/\n/g, "<br>");
    }).join("");
  }

  function addMessage(role, text, sources, isError) {
    const wrapper = document.createElement("div");
    wrapper.className = "message " + role + (isError ? " error" : "");
    const meta = document.createElement("div");
    meta.className = "message-meta";
    meta.textContent = role === "user" ? "You" : (isError ? "Notice" : "M365Buddy Assistant");
    wrapper.appendChild(meta);
    const content = document.createElement("div");
    content.innerHTML = renderMarkdown(text);
    wrapper.appendChild(content);

    if (Array.isArray(sources) && sources.length) {
      const sourceBox = document.createElement("div");
      sourceBox.className = "source-links";
      const heading = document.createElement("div");
      heading.textContent = "Related M365Buddy articles";
      sourceBox.appendChild(heading);
      sources.forEach(function (source) {
        if (!source || typeof source.title !== "string" || typeof source.url !== "string") return;
        let parsed;
        try { parsed = new URL(source.url, location.origin); } catch { return; }
        if (parsed.origin !== location.origin || !parsed.pathname.startsWith("/articles/")) return;
        const link = document.createElement("a");
        link.href = parsed.pathname + parsed.search;
        link.textContent = source.title;
        sourceBox.appendChild(link);
      });
      if (sourceBox.querySelectorAll("a").length) wrapper.appendChild(sourceBox);
    }

    messages.appendChild(wrapper);
    messages.scrollTop = messages.scrollHeight;
    return wrapper;
  }

  function getRelevantSources(question) {
    const search = window.M365BuddySearch;
    if (!search || typeof search.search !== "function") return [];
    const seen = new Set();
    return search.search(question).filter(function (item) {
      if (!item || typeof item.url !== "string" || !item.url.startsWith("/articles/") || seen.has(item.url)) return false;
      seen.add(item.url);
      return true;
    }).slice(0, 3).map(function (item) { return item.url; });
  }

  function showTyping() {
    const node = document.createElement("div");
    node.className = "message assistant";
    node.id = "assistant-typing";
    node.innerHTML = '<div class="message-meta">M365Buddy Assistant</div><span class="typing" aria-label="Thinking"><span></span><span></span><span></span></span>';
    messages.appendChild(node);
    messages.scrollTop = messages.scrollHeight;
    return node;
  }

  async function ask(question) {
    if (busy || !question.trim()) return;
    busy = true;
    send.disabled = true;
    input.disabled = true;
    const welcome = document.getElementById("welcome");
    if (welcome) welcome.remove();
    addMessage("user", question.trim());
    const typing = showTyping();
    try {
      const response = await fetch("/api/assistant", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          question: question.trim(),
          history: history.slice(-6),
          sources: getRelevantSources(question.trim())
        })
      });
      let data;
      try { data = await response.json(); } catch { data = {}; }
      typing.remove();
      if (!response.ok) throw new Error(data.error || "The assistant is temporarily unavailable. Please try again.");
      if (!data.answer) throw new Error("The assistant returned an empty response. Please try again.");
      addMessage("assistant", data.answer, data.sources || []);
      history.push({ role: "user", content: question.trim() }, { role: "assistant", content: data.answer });
      history = history.slice(-6);
    } catch (error) {
      typing.remove();
      addMessage("assistant", error.message || "Something went wrong. Please try again.", [], true);
    } finally {
      busy = false;
      send.disabled = false;
      input.disabled = false;
      input.focus();
    }
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    const question = input.value.trim();
    if (!question || busy) return;
    input.value = "";
    input.style.height = "auto";
    ask(question);
  });

  input.addEventListener("input", function () {
    input.style.height = "auto";
    input.style.height = Math.min(input.scrollHeight, 150) + "px";
  });

  messages.addEventListener("click", function (event) {
    const chip = event.target.closest(".prompt-chip");
    if (!chip || busy) return;
    input.value = chip.textContent.trim();
    input.focus();
    input.dispatchEvent(new Event("input"));
  });

  reset.addEventListener("click", function () {
    if (busy) return;
    history = [];
    messages.innerHTML = '<div class="welcome" id="welcome"><h2>New conversation</h2><div>Ask a Microsoft 365 question or choose a suggested prompt.</div><div class="prompts"><button class="prompt-chip" type="button">Create a SharePoint site inventory report</button><button class="prompt-chip" type="button">Troubleshoot PnP certificate authentication</button><button class="prompt-chip" type="button">Explain Microsoft Graph app permissions</button><button class="prompt-chip" type="button">Automate a report with Azure Automation</button></div></div>';
    input.value = "";
    input.focus();
  });
})();
