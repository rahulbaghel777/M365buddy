(function () {
  "use strict";
  if (window.__m365BuddyChatInstalled || location.pathname.startsWith("/assistant")) return;
  window.__m365BuddyChatInstalled = true;

  const css = `
  #m365-chat-launcher{position:fixed;right:24px;bottom:22px;z-index:9998;display:flex;align-items:center;gap:10px;border:0;border-radius:999px;padding:13px 18px;background:linear-gradient(135deg,#0878ee,#0757b8);color:#fff;font:700 14px/1.2 Inter,"Segoe UI",Arial,sans-serif;box-shadow:0 8px 28px rgba(7,67,145,.3);cursor:pointer;transition:transform .18s,box-shadow .18s}
  #m365-chat-launcher:hover{transform:translateY(-2px);box-shadow:0 12px 32px rgba(7,67,145,.36)}
  #m365-chat-launcher .m365-bot-icon{width:28px;height:28px;display:grid;place-items:center;border-radius:50%;background:rgba(255,255,255,.18)}
  #m365-chat-launcher svg{width:18px;height:18px}
  #m365-chat-panel{position:fixed;right:24px;bottom:88px;z-index:9999;width:min(390px,calc(100vw - 24px));height:min(590px,calc(100dvh - 115px));min-height:360px;display:none;flex-direction:column;overflow:hidden;border:1px solid #d6e2f0;border-radius:18px;background:#fff;color:#152b49;box-shadow:0 20px 70px rgba(7,26,61,.26);font:14px/1.5 Inter,"Segoe UI",Arial,sans-serif}
  #m365-chat-panel.is-open{display:flex;animation:m365-chat-in .16s ease-out}
  @keyframes m365-chat-in{from{opacity:0;transform:translateY(8px) scale(.985)}to{opacity:1;transform:translateY(0) scale(1)}}
  #m365-chat-panel *{box-sizing:border-box}
  .m365-chat-head{display:flex;align-items:center;gap:10px;padding:15px 15px;background:linear-gradient(115deg,#07346f,#0878ee);color:#fff}
  .m365-chat-avatar{display:grid;place-items:center;flex:0 0 36px;width:36px;height:36px;border-radius:12px;background:rgba(255,255,255,.17)}
  .m365-chat-avatar svg{width:22px;height:22px}
  .m365-chat-head-copy{flex:1;min-width:0}
  .m365-chat-title{font-weight:800;font-size:14px;line-height:1.3}
  .m365-chat-subtitle{font-size:11px;color:#d8eaff;margin-top:3px}
  .m365-chat-head-actions{display:flex;gap:5px}
  .m365-chat-icon-button{width:31px;height:31px;display:grid;place-items:center;border:0;border-radius:8px;background:rgba(255,255,255,.13);color:#fff;cursor:pointer;font-size:19px}
  .m365-chat-icon-button:hover{background:rgba(255,255,255,.23)}
  .m365-chat-body{flex:1;min-height:0;overflow:auto;padding:14px;background:#f7faff;display:flex;flex-direction:column;gap:11px;scroll-behavior:smooth}
  .m365-chat-welcome{padding:14px;border:1px solid #e0e9f4;border-radius:13px;background:#fff;color:#536984;font-size:12px}
  .m365-chat-welcome strong{display:block;color:#132b4c;font-size:14px;margin-bottom:5px}
  .m365-chat-suggestions{display:flex;flex-direction:column;align-items:flex-start;gap:7px;margin-top:12px}
  .m365-chat-suggestion{max-width:100%;padding:8px 10px;border:1px solid #cbdff5;border-radius:9px;background:#f7fbff;color:#1b568f;font:600 11px/1.35 Inter,"Segoe UI",Arial,sans-serif;text-align:left;cursor:pointer}
  .m365-chat-suggestion:hover{background:#e9f4ff;border-color:#93c5fd}
  .m365-chat-message{max-width:94%;padding:10px 12px;border:1px solid #e1e8f1;border-radius:12px;background:#fff;color:#263d5b;font-size:12px;overflow-wrap:anywhere}
  .m365-chat-message.user{align-self:flex-end;background:#e8f3ff;border-color:#c8e0fb;color:#143f6d}
  .m365-chat-message.error{background:#fff5f5;border-color:#fecaca;color:#991b1b}
  .m365-chat-message a{color:#075fc4;text-decoration:underline}
  .m365-chat-message pre{max-width:100%;overflow:auto;padding:10px;border-radius:8px;background:#0b1830;color:#eaf2ff;font:11px/1.5 ui-monospace,Consolas,monospace;white-space:pre}
  .m365-chat-message code{font:11px ui-monospace,Consolas,monospace}
  .m365-chat-sources{padding-top:8px;margin-top:8px;border-top:1px solid #e6edf5}
  .m365-chat-sources a{display:block;margin-top:5px;font-size:11px;font-weight:700}
  .m365-chat-typing{display:flex;gap:4px;padding:10px 12px}
  .m365-chat-typing i{width:6px;height:6px;border-radius:50%;background:#7c91ad;animation:m365-chat-pulse .7s infinite alternate}
  .m365-chat-typing i:nth-child(2){animation-delay:.2s}.m365-chat-typing i:nth-child(3){animation-delay:.4s}
  @keyframes m365-chat-pulse{to{opacity:.25;transform:translateY(-3px)}}
  .m365-chat-compose{padding:11px;border-top:1px solid #e3ebf5;background:#fff}
  .m365-chat-compose form{display:flex;align-items:flex-end;gap:7px}
  #m365-chat-input{flex:1;min-width:0;max-height:105px;min-height:42px;resize:none;padding:10px 11px;border:1px solid #cbd9e9;border-radius:10px;outline:none;color:#152b49;background:#fff;font:12px/1.4 Inter,"Segoe UI",Arial,sans-serif}
  #m365-chat-input:focus{border-color:#6eaeef;box-shadow:0 0 0 3px rgba(8,120,238,.1)}
  #m365-chat-send{width:42px;height:42px;flex:0 0 42px;display:grid;place-items:center;border:0;border-radius:10px;background:#0878ee;color:#fff;cursor:pointer}
  #m365-chat-send:disabled{opacity:.55;cursor:wait}
  #m365-chat-send svg{width:18px;height:18px}
  .m365-chat-footnote{margin:7px 2px 0;color:#8290a4;font-size:9px;line-height:1.4}
  @media(max-width:520px){#m365-chat-launcher{right:14px;bottom:14px;padding:11px 14px}#m365-chat-panel{right:8px;bottom:72px;width:calc(100vw - 16px);height:min(620px,calc(100dvh - 90px));min-height:320px;border-radius:15px}}
  @media(prefers-reduced-motion:reduce){#m365-chat-panel.is-open{animation:none}#m365-chat-launcher{transition:none}#m365-chat-body{scroll-behavior:auto}}
  `;
  const style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);

  const root = document.createElement("div");
  root.innerHTML = `
    <button id="m365-chat-launcher" type="button" aria-label="Open M365Buddy AI chat" aria-expanded="false" aria-controls="m365-chat-panel">
      <span class="m365-bot-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3v3m-6 4h12a3 3 0 0 1 3 3v4a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3v-4a3 3 0 0 1 3-3Z"/><path d="M8 14h.01M16 14h.01M9 17h6"/></svg></span>
      <span>Ask M365Buddy</span>
    </button>
    <section id="m365-chat-panel" role="dialog" aria-label="Chat with M365Buddy" aria-modal="false">
      <header class="m365-chat-head">
        <div class="m365-chat-avatar" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3v3m-6 4h12a3 3 0 0 1 3 3v4a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3v-4a3 3 0 0 1 3-3Z"/><path d="M8 14h.01M16 14h.01M9 17h6"/></svg></div>
        <div class="m365-chat-head-copy"><div class="m365-chat-title">M365Buddy Assistant</div><div class="m365-chat-subtitle">Microsoft 365 help · AI-powered</div></div>
        <div class="m365-chat-head-actions"><button type="button" class="m365-chat-icon-button" id="m365-chat-new" aria-label="Start a new chat" title="New chat">↻</button><button type="button" class="m365-chat-icon-button" id="m365-chat-close" aria-label="Close chat" title="Close">×</button></div>
      </header>
      <div class="m365-chat-body" id="m365-chat-body" role="log" aria-live="polite" aria-relevant="additions text">
        <div class="m365-chat-welcome" id="m365-chat-welcome"><strong>Hi! How can I help?</strong>Ask about SharePoint, PowerShell, Entra ID, Teams, OneDrive, Microsoft Graph or automation.<div class="m365-chat-suggestions"><button type="button" class="m365-chat-suggestion">Create a SharePoint site inventory report</button><button type="button" class="m365-chat-suggestion">Troubleshoot PnP certificate authentication</button><button type="button" class="m365-chat-suggestion">Explain Microsoft Graph permissions</button></div></div>
      </div>
      <div class="m365-chat-compose"><form id="m365-chat-form"><label for="m365-chat-input" style="position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap">Ask a Microsoft 365 question</label><textarea id="m365-chat-input" rows="1" maxlength="1200" placeholder="Ask a question…" required></textarea><button id="m365-chat-send" type="submit" aria-label="Send question"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m4 12 16-8-5 16-3-7-8-1Z"/><path d="m12 13 8-9"/></svg></button></form><div class="m365-chat-footnote">AI answers may be incomplete or out of date. Don’t enter passwords, tokens or private keys.</div></div>
    </section>`;
  document.body.appendChild(root);

  const launcher = document.getElementById("m365-chat-launcher");
  const panel = document.getElementById("m365-chat-panel");
  const close = document.getElementById("m365-chat-close");
  const newChat = document.getElementById("m365-chat-new");
  const form = document.getElementById("m365-chat-form");
  const input = document.getElementById("m365-chat-input");
  const send = document.getElementById("m365-chat-send");
  const body = document.getElementById("m365-chat-body");
  let history = [];
  let busy = false;

  function esc(value) {
    return String(value ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
  }
  function markdown(value) {
    return String(value ?? "").split(/(```[a-zA-Z0-9_-]*\n[\s\S]*?```)/g).map(part => {
      if (part.startsWith("```")) return "<pre><code>" + esc(part.replace(/^```[a-zA-Z0-9_-]*\n?/, "").replace(/```$/, "")) + "</code></pre>";
      let safe = esc(part);
      safe = safe.replace(/\[([^\]]+)\]\((https:\/\/[^\s)]+|\/(?!\/)[^\s)]+)\)/g, (_, label, href) => '<a href="' + href + '"' + (href.startsWith("https://") ? ' target="_blank" rel="noopener noreferrer"' : "") + ">" + label + "</a>");
      safe = safe.replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
      return safe.replace(/\n/g, "<br>");
    }).join("");
  }
  function relevantSources(question) {
    const api = window.M365BuddySearch;
    if (!api || typeof api.search !== "function") return [];
    return api.search(question).filter(item => item && typeof item.url === "string" && item.url.startsWith("/articles/")).slice(0,3).map(item => item.url);
  }
  function addMessage(role, text, sources, error) {
    const node = document.createElement("div");
    node.className = "m365-chat-message " + role + (error ? " error" : "");
    node.innerHTML = markdown(text);
    if (Array.isArray(sources) && sources.length) {
      const box = document.createElement("div");
      box.className = "m365-chat-sources";
      const title = document.createElement("strong");
      title.textContent = "Related M365Buddy guides";
      box.appendChild(title);
      sources.forEach(source => {
        if (!source || typeof source.title !== "string" || typeof source.url !== "string") return;
        let url;
        try { url = new URL(source.url, location.origin); } catch { return; }
        if (url.origin !== location.origin || !url.pathname.startsWith("/articles/")) return;
        const link = document.createElement("a");
        link.href = url.pathname + url.search;
        link.textContent = source.title;
        box.appendChild(link);
      });
      if (box.querySelector("a")) node.appendChild(box);
    }
    body.appendChild(node);
    body.scrollTop = body.scrollHeight;
    return node;
  }
  function typing() {
    const node = document.createElement("div");
    node.className = "m365-chat-message m365-chat-typing";
    node.innerHTML = "<i></i><i></i><i></i>";
    body.appendChild(node);
    body.scrollTop = body.scrollHeight;
    return node;
  }
  function openPanel() {
    panel.classList.add("is-open");
    launcher.setAttribute("aria-expanded", "true");
    launcher.style.display = "none";
    input.focus();
  }
  function closePanel() {
    panel.classList.remove("is-open");
    launcher.style.display = "flex";
    launcher.setAttribute("aria-expanded", "false");
    launcher.focus();
  }
  async function ask(question) {
    if (busy || !question.trim()) return;
    busy = true;
    send.disabled = true;
    input.disabled = true;
    const welcome = document.getElementById("m365-chat-welcome");
    if (welcome) welcome.remove();
    addMessage("user", question.trim());
    const pending = typing();
    try {
      const response = await fetch("/api/assistant", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ question: question.trim(), history: history.slice(-6), sources: relevantSources(question.trim()) })
      });
      let data = {};
      try { data = await response.json(); } catch {}
      pending.remove();
      if (!response.ok) throw new Error(data.error || "The assistant is temporarily unavailable. Please try again.");
      if (!data.answer) throw new Error("The assistant returned an empty response. Please try again.");
      addMessage("assistant", data.answer, data.sources || []);
      history.push({ role: "user", content: question.trim() }, { role: "assistant", content: data.answer });
      history = history.slice(-6);
    } catch (error) {
      pending.remove();
      addMessage("assistant", error.message || "Something went wrong. Please try again.", [], true);
    } finally {
      busy = false;
      send.disabled = false;
      input.disabled = false;
      input.focus();
    }
  }

  launcher.addEventListener("click", openPanel);
  close.addEventListener("click", closePanel);
  newChat.addEventListener("click", () => {
    if (busy) return;
    history = [];
    body.innerHTML = '<div class="m365-chat-welcome" id="m365-chat-welcome"><strong>New conversation</strong>Ask a Microsoft 365 question or choose a suggested prompt.<div class="m365-chat-suggestions"><button type="button" class="m365-chat-suggestion">Create a SharePoint site inventory report</button><button type="button" class="m365-chat-suggestion">Troubleshoot PnP certificate authentication</button><button type="button" class="m365-chat-suggestion">Explain Microsoft Graph permissions</button></div></div>';
    input.value = "";
    input.focus();
  });
  form.addEventListener("submit", event => {
    event.preventDefault();
    const question = input.value.trim();
    if (!question || busy) return;
    input.value = "";
    input.style.height = "auto";
    ask(question);
  });
  input.addEventListener("input", () => { input.style.height = "auto"; input.style.height = Math.min(input.scrollHeight, 105) + "px"; });
  body.addEventListener("click", event => {
    const chip = event.target.closest(".m365-chat-suggestion");
    if (!chip || busy) return;
    input.value = chip.textContent.trim();
    input.focus();
  });
  document.addEventListener("keydown", event => { if (event.key === "Escape" && panel.classList.contains("is-open")) closePanel(); });
})();