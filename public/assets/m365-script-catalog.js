/* Published M365Buddy script catalogue. Keep paths aligned with files under /scripts/. */
(function (global) {
  "use strict";
  global.M365BuddyScriptCatalog = [
    { name: "SharePoint Site Inventory", category: "SharePoint", description: "Inventory SharePoint Online sites and export site details to CSV.", path: "/scripts/SharePoint/SharePoint_Site_Inventory.ps1", tags: ["PnP PowerShell", "CSV", "Inventory"] },
    { name: "SharePoint Site Inventory + Graph Email", category: "SharePoint", description: "Inventory sites and deliver the report using Microsoft Graph app-only authentication.", path: "/scripts/SharePoint/SharePoint-Site-Inventory-GraphEmail.ps1", tags: ["Microsoft Graph", "Email", "CSV"] },
    { name: "SharePoint Site Inventory + Power Automate", category: "Power Automate", description: "Generate a SharePoint site inventory for Power Automate report delivery.", path: "/scripts/SharePoint/SharePoint_Site_Inventory_PowerAutomate.ps1", tags: ["Power Automate", "PnP PowerShell", "CSV"] },
    { name: "SharePoint Site Inventory — Azure Automation", category: "Azure Automation", description: "Run SharePoint site inventory reporting as an Azure Automation runbook.", path: "/scripts/SharePoint/azure-automation-sharepoint-site-inventory.ps1", tags: ["Runbook", "Azure Automation", "PnP PowerShell"] },
    { name: "Microsoft Graph CSV Email Test", category: "Microsoft Graph", description: "Test sending a CSV report through Microsoft Graph.", path: "/scripts/SharePoint/Test-GraphCsvEmail-Fixed.ps1", tags: ["Microsoft Graph", "Email", "Test"] }
  ];
})(window);
