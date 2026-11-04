# 📊 Datasets - AI & Fabric Hackathon

This folder contains the data needed for the AI & Fabric Hackathon.

---

## 🚀 UPLOAD DATA TO AZURE

### 1️⃣ Open Azure Cloud Shell (click the button)

[![Open Cloud Shell](https://learn.microsoft.com/en-us/azure/cloud-shell/media/embed-cloud-shell/launch-cloud-shell-1.png)](https://shell.azure.com/powershell)

---

### 2️⃣ Copy and paste this command into Cloud Shell

```powershell
git clone https://github.com/DCSA-HackLabs/Hackathon-English.git; cd Hackathon-English; ./run-data-loader.ps1
```

<details>
<summary>📋 Click here to copy the command</summary>

```
git clone https://github.com/DCSA-HackLabs/Hackathon-English.git; cd Hackathon-English; ./run-data-loader.ps1
```

</details>

---

> The script needs PowerShell 7 (the Cloud Shell default) and the **Storage Blob Data Contributor** role on the storage account for the PDF upload. Loading 100,000+ documents one at a time takes a while; add `-SkipPdfs` to load only Cosmos DB.

### 3️⃣ Enter your Resource Group when prompted

```
📌 Enter your Resource Group name: rg-fabric-challenge-YOURTEAM
```

---

## ✅ Done!

The script will automatically upload:

| File | Destination |
|------|-------------|
| 📄 `transactions.json` | **Cosmos DB** → FabricChallengeDB → transactions |
| 📄 `creditScore.json` | **Cosmos DB** → FabricChallengeDB → creditScore |
| 📄 `products.json` | **Cosmos DB** → FabricChallengeDB → products |
| 📁 `Financial Data.zip` (PDFs) | **Storage Account** → documents-pdf |

---

## 🔄 Process Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   📂 Datasets/                                                  │
│   ├── transactions.json  ──────►  🗄️ Cosmos DB                 │
│   ├── creditScore.json   ──────►  └── FabricChallengeDB         │
│   ├── products.json      ──────►      ├── transactions          │
│   │                                   ├── creditScore           │
│   │                                   └── products              │
│   │                                                             │
│   └── Financial Data.zip ──────►  📦 Storage Account           │
│       └── *.pdf                   └── documents-pdf/            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## ❓ Common Issues

| Error | Solution |
|------|----------|
| "Cosmos DB not found" | Verify the Resource Group name |
| "Resource Group does not exist" | Deploy the resources first using the ARM template |
| Authentication error | Run `az login` |
| "AuthorizationPermissionMismatch" on the PDF upload | Assign yourself **Storage Blob Data Contributor** on the storage account, wait a few minutes, and rerun with the same command |
| "keys with different casing" | You are on Windows PowerShell 5.1. Use PowerShell 7 (`pwsh`) or Cloud Shell |

If the script doesn't work for you, load the JSON files manually through Cosmos DB Data Explorer (**Items → Upload Item**), as described in [00-Solution.md](../00-Preparation-Landing-Zone/00-Solution.md).

---

## 📞 Support

Having issues? Contact the Microsoft team during the event.
