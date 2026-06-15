param(
    [Parameter(Mandatory = $true)]
    [int]$DaysToKeep,

    [Parameter(Mandatory = $true)]
    [string[]]$DriveLetters,

    [Alias("d")]
    [switch]$DryRun
)

function Send-StatusEmail {
    param(
        [string]$Subject,
        [string]$Body
    )

    $apiKey = [Environment]::GetEnvironmentVariable("SendGrid", "Process")
    if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("SendGrid", "User") }
    if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("SendGrid", "Machine") }

    if (-not $apiKey) {
        Write-Warning "SendGrid API key is not set."
        return
    }

    $payload = @{
        personalizations = @(
            @{
                to = @(
                    @{ email = "ecsproull765@gmail.com" }
                )
            }
        )
        from = @{
            email = "treasurer@scwwoodshop.com"
            name  = "SQL Backup Monitor"
        }
        subject = $Subject
        content = @(
            @{
                type  = "text/plain"
                value = $Body
            }
        )
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod `
        -Method Post `
        -Uri "https://api.sendgrid.com/v3/mail/send" `
        -Headers @{
            Authorization = "Bearer $apiKey"
            "Content-Type" = "application/json"
        } `
        -Body $payload `
        -ErrorAction Stop
}

$normalizedDrives = $DriveLetters |
    ForEach-Object { $_.Trim().TrimEnd(':').ToUpperInvariant() } |
    Where-Object { $_ -match '^[A-Z]$' } |
    Select-Object -Unique

if (-not $normalizedDrives) {
    throw "No valid drive letters were provided. Example: -DriveLetters C,D"
}

$folders = foreach ($drive in $normalizedDrives) {
    "${drive}:\LocalSqlBackup\Accounting_live\Full"
    "${drive}:\LocalSqlBackup\Accounting_live\Logs"
}

$cutoff = (Get-Date).AddDays(-$DaysToKeep)
$matchedCount = 0
$deletedCount = 0
$bytesDeleted = 0
$remainingSummary = ""

Write-Host "Cleaning files older than $DaysToKeep days"
Write-Host "Cutoff date: $cutoff"
Write-Host "Drives: $($normalizedDrives -join ', ')"

if ($DryRun) {
    Write-Host "*** DRY RUN - No files will be deleted ***"
}

Write-Host ""

try {
    foreach ($folder in $folders)
    {
        if (Test-Path $folder)
        {
            Write-Host "Checking $folder"

            Get-ChildItem $folder -File -ErrorAction Stop |
            Where-Object {
                $_.Extension -in ".bak", ".trn" -and
                $_.LastWriteTime -lt $cutoff
            } |
            ForEach-Object {

                if ($DryRun) {
                    Write-Host "Would delete: $($_.FullName)"
                }
                else {
                    Write-Host "Deleting: $($_.FullName)"
                    Remove-Item $_.FullName -Force -ErrorAction Stop
                    $deletedCount++
                    $bytesDeleted += $_.Length
                }

                $matchedCount++
            }

            $remaining = Get-ChildItem $folder -File -ErrorAction Stop |
            Where-Object {
                $_.Extension -in ".bak", ".trn"
            }
            $remainingSummary += "${folder}: $($remaining.Count) files`r`n"
        }
        else
        {
            Write-Warning "Folder not found: $folder"
        }
    }

    $body = @"
SQL Backup Cleanup Complete

Retention days: $DaysToKeep
Drives: $($normalizedDrives -join ', ')
Dry run: $DryRun
Cutoff: $cutoff

Files matched: $matchedCount
Files deleted: $deletedCount
Bytes reclaimed: $([math]::Round($bytesDeleted / 1GB, 2)) GB

Remaining:
$remainingSummary
"@

    Send-StatusEmail `
        -Subject "SQL Backup Cleanup OK - $env:COMPUTERNAME" `
        -Body $body
}
catch {
    $errorMessage = $_.Exception.Message
    $errorStack = $_.ScriptStackTrace

    $failureBody = @"
SQL Backup Cleanup FAILED

Retention days: $DaysToKeep
Drives: $($normalizedDrives -join ', ')
Dry run: $DryRun
Cutoff: $cutoff

Files matched before failure: $matchedCount
Files deleted before failure: $deletedCount
Bytes reclaimed before failure: $([math]::Round($bytesDeleted / 1GB, 2)) GB

Error: $errorMessage
Stack:
$errorStack
"@

    try {
        Send-StatusEmail `
            -Subject "SQL Backup Cleanup FAILED - $env:COMPUTERNAME" `
            -Body $failureBody
    }
    catch {
        Write-Warning "Failure email could not be sent: $($_.Exception.Message)"
    }

    throw
}