
const M365_INDEX = [
  {
    title: "Export All SharePoint Online Sites Using PnP PowerShell",
    type: "Article",
    category: "SharePoint",
    url: "/articles/sharepoint-online-site-inventory.html",
    description:
      "Generate a SharePoint Online site inventory and storage usage report using PnP PowerShell.",
    keywords: [
      "sharepoint",
      "site inventory",
      "storage",
      "pnp powershell",
      "powershell",
      "csv"
    ]
  },
  {
    title: "Register an Entra ID App for PnP PowerShell Certificate Authentication",
    type: "Article",
    category: "Microsoft Entra",
    url: "/articles/entra-id-pnp-certificate-authentication.html",
    description:
      "Configure an Entra ID application, certificate, permissions and authentication for PnP PowerShell.",
    keywords: [
      "entra id",
      "certificate",
      "app registration",
      "pnp powershell",
      "admin consent"
    ]
  },
  {
    title: "SharePoint Storage Management",
    type: "Article",
    category: "SharePoint",
    url: "/articles/sharepoint-storage-management.html",
    description:
      "Understand SharePoint Online storage consumption and practical storage governance.",
    keywords: [
      "sharepoint",
      "storage",
      "quota",
      "capacity",
      "usage",
      "report"
    ]
  },
  {
    title: "SharePoint Site Lifecycle Management",
    type: "Article",
    category: "SharePoint",
    url: "/articles/sharepoint-site-lifecycle.html",
    description:
      "Manage inactive SharePoint sites with lifecycle and ownership processes.",
    keywords: [
      "sharepoint",
      "lifecycle",
      "inactive sites",
      "attestation",
      "governance"
    ]
  },
  {
    title: "SharePoint Version Management",
    type: "Article",
    category: "SharePoint",
    url: "/articles/sharepoint-version-management.html",
    description:
      "Understand SharePoint version history, version limits and storage governance.",
    keywords: [
      "sharepoint",
      "versions",
      "version history",
      "version limit",
      "storage"
    ]
  },
  {
    title: "Generate and Email a SharePoint Site Inventory Report with Microsoft Graph",
    type: "Article",
    category: "SharePoint",
    url: "/articles/powershell-report-delivery-microsoft-graph.html",
    description:
      "Generate a SharePoint site inventory, export the approved CSV, summarize storage and email the report with Microsoft Graph app-only certificate authentication.",
    keywords: ["sharepoint", "site inventory", "graph email", "powershell", "csv", "storage", "mail.send", "mail.readwrite", "certificate authentication"]
  },
  {
    title: "SharePoint Site Inventory + Graph Email PowerShell Script",
    type: "Script",
    category: "SharePoint",
    url: "/scripts/SharePoint/SharePoint-Site-Inventory-GraphEmail.ps1",
    description:
      "Published PowerShell script that inventories SharePoint sites, exports CSV and sends the report through Microsoft Graph.",
    keywords: ["sharepoint", "site inventory", "graph email", "powershell script", "csv attachment", "Mail.Send", "Mail.ReadWrite", "certificate"]
  },
  {
    title: "Email PowerShell Reports Using Power Automate",
    type: "Article",
    category: "Power Automate",
    url: "/articles/powershell-report-delivery-power-automate.html",
    description:
      "Use Power Automate and Microsoft 365 Outlook to email PowerShell CSV reports.",
    keywords: [
      "smtp",
      "email",
      "power automate",
      "outlook",
      "powershell",
      "csv"
    ]
  },
  {
    title: "SharePoint Site Inventory PowerShell Script",
    type: "Script",
    category: "SharePoint",
    url: "/scripts/SharePoint/sharepoint-site-inventory-viewer.html",
    description:
      "View the published SharePoint Online site inventory PowerShell script.",
    keywords: [
      "sharepoint",
      "powershell",
      "site inventory",
      "script"
    ]
  },
  {
    title: "SharePoint Version Report",
    type: "Script",
    category: "SharePoint",
    url: "/scripts/SharePoint/sharepoint-version-report.html",
    description:
      "SharePoint Online version usage reporting script.",
    keywords: [
      "sharepoint",
      "version report",
      "powershell"
    ]
  },
  {
    title: "SharePoint Recycle Bin Report",
    type: "Script",
    category: "SharePoint",
    url: "/scripts/SharePoint/sharepoint-recycle-bin-report.html",
    description:
      "SharePoint Online recycle bin reporting script.",
    keywords: [
      "sharepoint",
      "recycle bin",
      "powershell"
    ]
  },
  {title:"Create a Self-Signed Certificate for Microsoft Entra App Authentication",type:"Article",category:"Microsoft Entra",url:"/articles/entra-id-self-signed-certificate.html",description:"Create and export a PowerShell self-signed certificate, upload the public certificate, and protect the private key.",keywords:["entra id","certificate","self-signed","pfx","cer","powershell","authentication"]},
  {title:"Email SharePoint Inventory Reports with Power Automate",type:"Article",category:"Power Automate",url:"/articles/powershell-report-delivery-power-automate.html",description:"Create a SharePoint inventory CSV with PowerShell and deliver it using Power Automate, including certificate setup and troubleshooting.",keywords:["sharepoint","power automate","powershell","email report","csv","certificate","outlook"]},
  {title:"PowerShell Email Works Manually but Fails in Task Scheduler",type:"Article",category:"PowerShell",url:"/articles/PowerShell%20Email%20Works%20Manually%20but%20Fails%20in%20Task%20Scheduler.html",description:"Troubleshoot email scripts that work manually but fail in Windows Task Scheduler, including execution context and recipient formatting.",keywords:["powershell","task scheduler","email","smtp","scheduled task","troubleshooting"]}

  ,{
    title: "Automate SharePoint Online Site Inventory with Azure Automation",
    type: "Article",
    category: "Azure Automation",
    url: "/articles/azure-automation-sharepoint-site-inventory.html",
    description: "Configure and schedule a SharePoint Online inventory runbook with PnP.PowerShell, Azure Automation and Microsoft Graph.",
    keywords: ["azure automation","runbook","sharepoint","site inventory","pnp powershell","graph","schedule","storage","report"]
  },
  {
    title: "SharePoint Site Inventory with PnP PowerShell",
    type: "Script",
    category: "SharePoint",
    url: "/scripts/SharePoint/SharePoint_Site_Inventory.ps1",
    description: "Download the SharePoint Online site inventory PowerShell script.",
    keywords: ["sharepoint","site inventory","pnp powershell","download","csv","storage"]
  },
  {
    title: "SharePoint Site Inventory with Power Automate",
    type: "Script",
    category: "SharePoint",
    url: "/scripts/SharePoint/SharePoint_Site_Inventory_PowerAutomate.ps1",
    description: "Download the site inventory script designed for Power Automate report delivery.",
    keywords: ["sharepoint","site inventory","power automate","powershell","csv","email"]
  },
  {
    title: "SharePoint Site Inventory with Azure Automation",
    type: "Script",
    category: "Azure Automation",
    url: "/scripts/SharePoint/azure-automation-sharepoint-site-inventory.ps1",
    description: "Download the Azure Automation runbook script for SharePoint site inventory reporting.",
    keywords: ["azure automation","runbook","sharepoint","inventory","powershell","graph"]
  },
  {
    title: "Microsoft Graph CSV Email Test Script",
    type: "Script",
    category: "Microsoft Graph",
    url: "/scripts/SharePoint/Test-GraphCsvEmail-Fixed.ps1",
    description: "Download a PowerShell test script for sending CSV reports through Microsoft Graph.",
    keywords: ["graph","csv","email","powershell","mail.send","test"]
  },
];

 
// Shared search API used by pages that load this asset.
(function (global) {
  "use strict";
  const normalize = value => String(value || "").toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, " ").trim();
  function search(query, type) {
    const q = normalize(query);
    if (!q) return [];
    const terms = q.split(/\s+/).filter(Boolean);
    return M365_INDEX.map(item => {
      const title = normalize(item.title), category = normalize(item.category), description = normalize(item.description);
      const keywords = normalize((item.keywords || []).join(" "));
      const all = normalize([item.title, item.category, item.description, ...(item.keywords || [])].join(" "));
      let score = 0;
      if (title === q) score += 100;
      if (title.includes(q)) score += 35;
      if (category.includes(q)) score += 18;
      if (keywords.includes(q)) score += 22;
      if (description.includes(q)) score += 8;
      terms.forEach(term => {
        if (title.includes(term)) score += 12;
        if (keywords.includes(term)) score += 8;
        if (category.includes(term)) score += 5;
        if (description.includes(term)) score += 2;
      });
      const matched = terms.filter(term => all.includes(term)).length;
      if (matched < terms.length) score = Math.max(0, score - (terms.length - matched) * 5);
      return Object.assign({}, item, { score });
    }).filter(item => item.score > 0 && (!type || type === "All" || item.type === type))
      .sort((a, b) => b.score - a.score || a.title.localeCompare(b.title));
  }
  global.M365BuddySearch = { index: M365_INDEX, search: search };
})(window);
