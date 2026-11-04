# 🏆 Challenge 07: Automate Document Processing with Logic Apps 🚀

## 📖 Objective

In this challenge you must:

✅ Configure an **Azure Logic App** to automatically process PDF files  
✅ Enable **Managed Identity** for secure resource access  
✅ Assign **permissions** to the Logic App for storage and AI processing  
✅ Use **Document Intelligence (Form Recognizer)** to analyze PDFs  
✅ Create a **Data Factory copy job or pipeline in Fabric** to move PDFs from **Fabric** to a **Storage Account**  
✅ Save the **analyzed JSON** files in the **Storage Account**  
✅ Verify that the **processed files** are stored correctly in the **Storage Account**

### 📦 Before you start

- **Input PDFs:** the sample documents are in `Datasets/Financial Data.zip` (12,000 "Contoso Investments" portfolio statements). Extract a small batch (for example 10 files) and upload them to your Lakehouse **Files** section. The pipeline in this challenge then copies them from Fabric to the storage account.
- **Containers:** the Challenge 0 template creates `documents-pdf` (input) and `ai-processed` (output) in the storage account.
- **Document Intelligence tier:** the Free (F0) tier allows 500 pages per month and 20 calls per minute. Process a small batch on F0; all 12,000 files need the S0 tier.
- **Your own access:** the Fabric copy signs in as you, so you need the **Storage Blob Data Contributor** role on the storage account. Subscription Owner doesn't include access to blob data.
- **Personal data:** the PDFs contain synthetic names, emails and addresses, and the extracted JSON will too. In a real project, decide which fields you need before storing the output, as you did for SSNs in Challenge 1.

> ℹ️ The Logic Apps **legacy designer** reaches end of support in December 2026. If your portal opens the new designer, the action names below are the same but the layout differs.

---

## 🚀 Step 1: Create a Logic App

💡 **Why?** The Logic App will automate detection of new PDF files and trigger analysis with **Document Intelligence**.

### 1️⃣ Create an Azure Logic App
🔹 In the **Azure Portal**, create a new **Logic App (Consumption Plan)**.

🔹 **What settings should you define during creation?**

✅ **Result**: A Logic App is created and ready to be configured.

---

## 🚀 Step 2: Enable Managed Identity for the Logic App

💡 **Why?** The Logic App needs secure authentication to interact with **Azure Storage** and **Document Intelligence**.

### 1️⃣ Enable System-Assigned Identity
🔹 In the **Logic App** settings, enable the **System-Assigned Identity** option.

🔹 **Where can you copy the Object (Principal) ID to use later?**

✅ **Result**: The Logic App has an identity for authentication.

---

## 🚀 Step 3: Assign Permissions to the Logic App

💡 **Why?** The Logic App needs **access** to read PDFs from **Blob Storage**, call **Document Intelligence**, and write JSON back to the **Storage Account**. Grant only the roles it needs (least privilege).

### 1️⃣ Assign IAM permissions to the Logic App
🔹 Go to **Storage Account and Document Intelligence** → **Access Control (IAM)**

🔹 Assign the following **roles** to the Logic App’s **Managed Identity**:
✅ **Storage Blob Data Contributor** on the storage account (read PDFs, write JSON)  
✅ **Cognitive Services User** on Document Intelligence (call the analyze API)

⚠️ Don't assign **Storage Account Contributor**: it can read the account's access keys, which gives full access to everything in the account, and the Logic App doesn't need it. **Cognitive Services Contributor** manages the resource; the role for *calling* the service is **Cognitive Services User**.

🔹 When you create the Logic App's connections to Blob Storage and Document Intelligence, choose **Logic Apps Managed Identity** as the authentication type, so no keys are stored.

🔹 **Why are these roles important for document processing?**

✅ **Result**: The Logic App can now access **Blob Storage** and **AI services**.

---

## 🚀 Step 4: Configure the Logic App using the Azure Portal (Designer)

💡 **Why?** You need to define the workflow to process incoming PDFs.

### 1️⃣ Create the workflow in Logic App Designer
🔹 Open the **Logic App Designer** → Start with a **Blank Logic App**

🔹 **Trigger:**  
✅ Add **"When a blob is added or modified (properties only)"  
✅ **Select the storage account**: `(Your Storage Account)`  
✅ **Select the container**: `documents-pdf`  
✅ Add a **condition**: only trigger for `.pdf` files

🔹 **Read the file:**  
✅ Add **"Get blob content (V2)"** for the blob that triggered the run

🔹 **Processing step:**  
✅ Add **"Analyze Document for Prebuilt or Custom models (v3.x API)"**  
✅ **Model:** `prebuilt-layout`. The sample PDFs are portfolio statements, not invoices, so `prebuilt-invoice` doesn't fit  
✅ **Document/Image File Content:** the content from *Get blob content*. Sending the file bytes means Document Intelligence doesn't need its own access to your storage account, which a URL would require

🔹 **Save the output:**  
✅ Add **"Create Blob"** in **Azure Blob Storage**  
✅ **Select the container**: `ai-processed`  
✅ **Define the blob name:**

```plaintext
analyzed-document-@{triggerOutputs()?['body']['name']}.json
```

---

## 🚀 Step 5: Copy PDFs from Fabric to the Storage Account

💡 **Why?** Documents often land in the lakehouse first. A copy job moves them to the storage account the Logic App watches.

🔹 In your Fabric workspace, create a **Copy job** (Data Factory).  
✅ **Source:** your Lakehouse → **Files**, with **Wildcard file path** `*.pdf`  
✅ **File format:** binary copy (schema agnostic), so the PDFs are copied byte for byte  
✅ **Destination:** Azure Blob Storage → your storage account → `documents-pdf` container  
✅ **Copy mode:** incremental, so each run only copies new files

🔹 Run the copy job. (Optional: wrap it in a **pipeline** with a **Copy job** activity to schedule it with other steps.)

✅ **Result**: The PDFs are in `documents-pdf`, and the Logic App picks them up within a minute.

---

## 🚀 Step 6: Verify the Results

🔹 Open the `ai-processed` container and check that there is one JSON file per PDF.  
🔹 Open one JSON file and find the extracted text and tables.  
🔹 In the Logic App, open **Run history** and check that each run succeeded.

✅ **Result**: Every PDF has a matching analysis JSON in the storage account.

📄 A sample workflow definition is in [LogicApp.json](LogicApp.json). Replace the `<<...>>` placeholders, or use it as a reference in the designer's **Code view**.
