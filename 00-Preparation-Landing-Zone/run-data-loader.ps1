#Requires -Version 7.0
<#
.SYNOPSIS
    Loads JSON data into Cosmos DB and PDF files into the deployed storage account.

.DESCRIPTION
    This script:
    1. Loads transactions.json into Cosmos DB (transactions container)
    2. Loads creditScore.json into Cosmos DB (creditScore container)
    3. Loads products.json into Cosmos DB (products container)
    4. Extracts and uploads PDF files from "Financial Data.zip" to the Storage Account (documents-pdf container)

    Container names and partition keys match azuredeploy.json: every container is partitioned on /id.
    If a container is missing, the script creates it with the same settings.

    Requires PowerShell 7 (the default in Azure Cloud Shell). creditScore.json has both "ID" and "id"
    fields, which only ConvertFrom-Json -AsHashtable can read.

.PARAMETER ResourceGroupName
    Name of the Resource Group where the resources were deployed.

.PARAMETER SkipPdfs
    Skip the PDF upload (for example, when you only need the Cosmos DB data).

.EXAMPLE
    ./run-data-loader.ps1 -ResourceGroupName "rg-fabric-challenge-test"

.EXAMPLE
    # From Azure Cloud Shell (PowerShell):
    # git clone https://github.com/DCSA-HackLabs/Hackathon-English.git; cd Hackathon-English; ./run-data-loader.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Name of the Resource Group")]
    [string]$ResourceGroupName,

    [switch]$SkipPdfs
)

$ErrorActionPreference = "Stop"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Step { param([string]$Message) Write-Host "`n📌 $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "ℹ️  $Message" -ForegroundColor Yellow }
function Write-ErrorMsg { param([string]$Message) Write-Host "❌ $Message" -ForegroundColor Red }

# Insert (upsert) one document into Cosmos DB through the REST API.
# Every container in azuredeploy.json is partitioned on /id, so the partition key value is always the id.
function Add-CosmosDocument {
    param(
        [string]$Endpoint,
        [string]$Key,
        [string]$Database,
        [string]$Container,
        [System.Collections.IDictionary]$Document,
        [ref]$LastError = $null
    )

    $resourceLink = "dbs/$Database/colls/$Container"
    $uri = "$Endpoint$resourceLink/docs"
    $date = [DateTime]::UtcNow.ToString("r")

    # Generate the authorization signature
    $keyBytes = [System.Convert]::FromBase64String($Key)
    $text = "post`ndocs`n$resourceLink`n$($date.ToLower())`n`n"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $keyBytes
    $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
    $signature = [System.Convert]::ToBase64String($hash)
    $authToken = [System.Web.HttpUtility]::UrlEncode("type=master&ver=1.0&sig=$signature")

    $partitionKeyValue = $Document["id"]

    $headers = @{
        "Authorization"                    = $authToken
        "x-ms-date"                        = $date
        "x-ms-version"                     = "2018-12-31"
        "Content-Type"                     = "application/json"
        "x-ms-documentdb-partitionkey"     = "[`"$partitionKeyValue`"]"
        "x-ms-documentdb-is-upsert"        = "true"
    }

    try {
        $body = $Document | ConvertTo-Json -Depth 10 -Compress
        $null = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -ContentType "application/json"
        return $true
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 409) {
            return $true  # Already exists
        }
        if ($null -ne $LastError) {
            $LastError.Value = $_.Exception.Message
        }
        return $false
    }
}

# Create the database and container if they don't exist, with the same settings as azuredeploy.json.
function Initialize-CosmosContainer {
    param([string]$Account, [string]$ResourceGroup, [string]$Database, [string]$Container)

    $dbExists = az cosmosdb sql database show --account-name $Account --resource-group $ResourceGroup --name $Database --output json 2>$null
    if (-not $dbExists) {
        Write-Info "Database '$Database' not found. Creating it..."
        az cosmosdb sql database create --account-name $Account --resource-group $ResourceGroup --name $Database --output none
    }

    $containerExists = az cosmosdb sql container show --account-name $Account --resource-group $ResourceGroup --database-name $Database --name $Container --output json 2>$null
    if (-not $containerExists) {
        Write-Info "Container '$Container' not found. Creating it (partition key /id)..."
        az cosmosdb sql container create --account-name $Account --resource-group $ResourceGroup --database-name $Database --name $Container --partition-key-path "/id" --output none
    }
}

# Read a JSON file and return its records as hashtables.
# -AsHashtable is required: creditScore.json has keys that differ only by case ("ID" and "id").
function Read-JsonRecords {
    param([string]$Path, [string]$WrapperProperty)

    $json = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if ($json -is [System.Collections.IList]) { return , $json }
    if ($json.ContainsKey($WrapperProperty)) { return , $json[$WrapperProperty] }
    if ($json.ContainsKey("data")) { return , $json["data"] }
    return , @($json)
}

# Load one JSON file into one container and report the counts.
function Import-JsonFile {
    param(
        [string]$FileName,
        [string]$Container,
        [string]$WrapperProperty,
        [string[]]$IdFallbackFields
    )

    Write-Step "Loading $FileName into Cosmos DB ($Container)..."

    $file = Get-ChildItem -Path $DatasetPath -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $file) {
        Write-ErrorMsg "$FileName not found in: $DatasetPath"
        $script:loadErrors++
        return
    }

    Initialize-CosmosContainer -Account $cosmosAccountName -ResourceGroup $ResourceGroupName -Database $DatabaseName -Container $Container

    $data = Read-JsonRecords -Path $file.FullName -WrapperProperty $WrapperProperty
    $total = $data.Count
    $loaded = 0
    $failed = 0
    $firstError = ""

    Write-Info "Found $total records to load..."
    $progressInterval = if ($total -lt 50) { 1 } elseif ($total -lt 200) { 10 } else { 50 }

    foreach ($document in $data) {
        # Cosmos DB requires an id, and it is also the partition key
        if (-not $document.ContainsKey("id")) {
            $fallback = $IdFallbackFields | Where-Object { $document.ContainsKey($_) } | Select-Object -First 1
            $document["id"] = if ($fallback) { [string]$document[$fallback] } else { [guid]::NewGuid().ToString() }
        }

        $errorRef = [ref]""
        $success = Add-CosmosDocument -Endpoint $cosmosEndpoint -Key $cosmosKey `
            -Database $DatabaseName -Container $Container -Document $document -LastError $errorRef

        if ($success) { $loaded++ } else {
            $failed++
            if ($failed -eq 1) { $firstError = $errorRef.Value }
        }

        $done = $loaded + $failed
        if (($done % $progressInterval -eq 0) -or ($done -eq $total)) {
            $percent = [math]::Round(($done / $total) * 100)
            Write-Host "`r  ⏳ Progress: $done / $total ($percent%) - ✅$loaded ❌$failed" -ForegroundColor Gray -NoNewline
        }
    }
    Write-Host ""

    if ($failed -gt 0) {
        Write-ErrorMsg "$Container : $loaded loaded / $failed failed / $total total"
        Write-Info "First error: $firstError"
        $script:loadErrors++
    }
    else {
        Write-Success "$Container : $loaded loaded / $total total"
    }
}

# ============================================================================
# BANNER
# ============================================================================
Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║   FABRIC HACKATHON - DATA LOADER                                             ║
║                                                                              ║
║   This script will load:                                                     ║
║   • transactions.json into Cosmos DB (transactions container)                ║
║   • creditScore.json into Cosmos DB (creditScore container)                  ║
║   • products.json into Cosmos DB (products container)                        ║
║   • Financial Data (PDFs) into the Storage Account                           ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Magenta

# ============================================================================
# INITIAL CHECKS
# ============================================================================

# Verify that Azure az CLI is installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-ErrorMsg "Azure CLI is not installed. Please install it first:"
    Write-Host "   https://learn.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Yellow
    exit 1
}

# Verify login in Azure
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Info "Logging in to Azure..."
    az login
}

# Prompt for Resource Group if not provided
if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    Write-Host ""
    $ResourceGroupName = Read-Host "📌 Enter the name of your Resource Group"
}

if ([string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    Write-ErrorMsg "You must provide a Resource Group name"
    exit 1
}

# Verify that the resource group exists
Write-Step "Verifying Resource Group: $ResourceGroupName"
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -ne "true") {
    Write-ErrorMsg "The Resource Group '$ResourceGroupName' does not exist"
    exit 1
}
Write-Success "Resource Group found"

# ============================================================================
# RETRIEVE RESOURCE INFORMATION
# ============================================================================
Write-Step "Retrieving information of deployed resources..."

# Cosmos DB
$cosmosAccount = az cosmosdb list --resource-group $ResourceGroupName --query "[0]" --output json | ConvertFrom-Json
if (-not $cosmosAccount) {
    Write-ErrorMsg "No Cosmos DB found in the Resource Group"
    exit 1
}
$cosmosAccountName = $cosmosAccount.name
$cosmosEndpoint = $cosmosAccount.documentEndpoint
Write-Success "Cosmos DB found: $cosmosAccountName"

# Retrieve the Azure Cosmos DB account key
$cosmosKeys = az cosmosdb keys list --name $cosmosAccountName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
$cosmosKey = $cosmosKeys.primaryMasterKey

# Storage Account
$storageAccount = az storage account list --resource-group $ResourceGroupName --query "[0]" --output json | ConvertFrom-Json
if (-not $storageAccount) {
    Write-ErrorMsg "No Storage Account found in the Resource Group"
    exit 1
}
$storageAccountName = $storageAccount.name
Write-Success "Storage Account found: $storageAccountName"

# ============================================================================
# DETERMINE DATASETS PATH
# ============================================================================
$DatasetPath = Join-Path $PSScriptRoot "Datasets"

# If it doesn't exist, try the current path
if (-not (Test-Path $DatasetPath)) {
    $DatasetPath = Join-Path (Get-Location) "Datasets"
}

# If it still doesn't exist, use the current directory
if (-not (Test-Path $DatasetPath)) {
    $DatasetPath = Get-Location
}

Write-Info "Searching files in: $DatasetPath"

# ============================================================================
# LOAD JSON DATA TO COSMOS DB
# ============================================================================
# Names match the containers created by azuredeploy.json
$DatabaseName = "FabricChallengeDB"
$script:loadErrors = 0

Import-JsonFile -FileName "transactions.json" -Container "transactions" `
    -WrapperProperty "transactions" -IdFallbackFields @("transaction_id", "transactionId")

Import-JsonFile -FileName "creditScore.json" -Container "creditScore" `
    -WrapperProperty "creditScores" -IdFallbackFields @("ID", "Customer_ID")

Import-JsonFile -FileName "products.json" -Container "products" `
    -WrapperProperty "products" -IdFallbackFields @("Internal ID", "Index")

# ============================================================================
# UPLOAD PDF FILES (FINANCIAL DATA ZIP) TO THE STORAGE ACCOUNT
# ============================================================================
if ($SkipPdfs) {
    Write-Info "Skipping PDF upload (-SkipPdfs)"
}
else {
    Write-Step "Processing Financial Data (PDFs) for Storage Account..."

    $pdfZipFile = Get-ChildItem -Path $DatasetPath -Filter "*Financial*Data*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($pdfZipFile) {
        Write-Info "ZIP found: $($pdfZipFile.Name)"

        # $env:TEMP is not set in Linux (including Cloud Shell); GetTempPath works on every platform
        $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) "pdf-extract-$(Get-Random)"
        New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

        try {
            Write-Info "Extracting files from ZIP..."
            Expand-Archive -Path $pdfZipFile.FullName -DestinationPath $tempFolder -Force

            $pdfCount = (Get-ChildItem -Path $tempFolder -Filter "*.pdf" -Recurse).Count
            if ($pdfCount -gt 0) {
                Write-Info "Uploading $pdfCount PDF files in one batch (this takes a few minutes)..."

                # One batched call instead of one az call per file. Requires the
                # Storage Blob Data Contributor role on the storage account (--auth-mode login).
                az storage blob upload-batch `
                    --account-name $storageAccountName `
                    --destination "documents-pdf" `
                    --source $tempFolder `
                    --pattern "*.pdf" `
                    --auth-mode login `
                    --overwrite `
                    --output none

                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorMsg "PDF upload failed. Check that you have the Storage Blob Data Contributor role on '$storageAccountName'."
                    $script:loadErrors++
                }
                else {
                    $uploaded = az storage blob list --account-name $storageAccountName --container-name "documents-pdf" `
                        --auth-mode login --num-results "*" --query "length([?ends_with(name, '.pdf')])" --output tsv
                    Write-Success "$uploaded PDF files are in the 'documents-pdf' container (expected $pdfCount)"
                }
            }
            else {
                Write-Info "No PDF files found in the ZIP"
            }
        }
        finally {
            if (Test-Path $tempFolder) {
                Remove-Item -Path $tempFolder -Recurse -Force
            }
        }
    }
    else {
        Write-ErrorMsg "No ZIP file matching '*Financial*Data*.zip' found in: $DatasetPath"
        $script:loadErrors++
    }
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================
if ($script:loadErrors -gt 0) {
    Write-Host "`n⚠️  DATA LOAD FINISHED WITH $($script:loadErrors) ERROR(S). Review the messages above." -ForegroundColor Red
}
else {
    Write-Host "`n🎉  DATA LOAD COMPLETED!" -ForegroundColor Green
}

Write-Host ""
Write-Host "📋 SUMMARY:" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Gray
Write-Host ""
Write-Host "🗄️  COSMOS DB: $cosmosAccountName" -ForegroundColor Yellow
Write-Host "   Database:   $DatabaseName"
Write-Host "   Container: transactions (data from transactions.json)"
Write-Host "   Container: creditScore (data from creditScore.json)"
Write-Host "   Container: products (data from products.json)"
Write-Host ""
Write-Host "📦 STORAGE ACCOUNT: $storageAccountName" -ForegroundColor Yellow
Write-Host "   Data container:"
Write-Host "   • documents-pdf  - Financial Data (PDFs)"
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Gray

Write-Host "`n🔗 CONNECT FROM FABRIC:" -ForegroundColor Cyan
Write-Host "   Cosmos DB Endpoint: $cosmosEndpoint"
Write-Host "   Storage Account:    https://$storageAccountName.dfs.core.windows.net/"
Write-Host ""

if ($script:loadErrors -gt 0) { exit 1 }
