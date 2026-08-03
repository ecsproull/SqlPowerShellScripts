# RestoreTime format is yyyy-MM-ddTHH:mm:ss
param(
    [datetime]$RestoreTime
)

$ErrorActionPreference = "Stop"

$server = ".\SQLEXPRESS"
$db     = "WoodClub"
$dbSource = "WoodClub"

$sourceFullFolder = "\\WC_SERVER\LocalSqlBackup\$dbSource\Full"
$sourceLogFolder  = "\\WC_SERVER\LocalSqlBackup\$dbSource\Logs"

$localFullFolder = "C:\LocalSqlBackup\$dbSource\Full"
$localLogFolder  = "C:\LocalSqlBackup\$dbSource\Logs"

$dataPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\$db.mdf"
$logPath  = "C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\$db.ldf"

Remove-Item "$localFullFolder\*" -Force -ErrorAction SilentlyContinue
Remove-Item "$localLogFolder\*"  -Force -ErrorAction SilentlyContinue

#
# Find the required FULL backup on the server.
#
$fullBackups = @(
    Get-ChildItem -LiteralPath $sourceFullFolder -Filter "*.bak" -File |
        Sort-Object LastWriteTime
)

if ($fullBackups.Count -eq 0)
{
    throw "No full backup files found in $sourceFullFolder."
}

if ($PSBoundParameters.ContainsKey("RestoreTime"))
{
    $full = $fullBackups |
        Where-Object { $_.LastWriteTime -le $RestoreTime } |
        Select-Object -Last 1

    if (-not $full)
    {
        throw "No full backup found at or before $RestoreTime."
    }

    Write-Host "Target restore time: $($RestoreTime.ToString('yyyy-MM-dd HH:mm:ss'))"
}
else
{
    $full = $fullBackups | Select-Object -Last 1
}

Write-Host "FULL: $($full.Name)"


#
# Determine exactly which transaction-log backups are required.
#
$allLogs = @(
    Get-ChildItem -LiteralPath $sourceLogFolder -Filter "*.trn" -File |
        Where-Object { $_.LastWriteTime -gt $full.LastWriteTime } |
        Sort-Object LastWriteTime
)

if ($PSBoundParameters.ContainsKey("RestoreTime"))
{
    $cutoffLog = $allLogs |
        Where-Object { $_.LastWriteTime -ge $RestoreTime } |
        Select-Object -First 1

    if (-not $cutoffLog)
    {
        throw "No log backup found that reaches restore time $RestoreTime."
    }

    $logs = @(
        $allLogs |
            Where-Object { $_.LastWriteTime -le $cutoffLog.LastWriteTime }
    )
}
else
{
    $logs = @($allLogs)
}

if ($logs.Count -eq 0)
{
    throw "No log files found after full backup $($full.Name)."
}


#
# Create the local staging directories.
#
New-Item -ItemType Directory -Path $localFullFolder -Force | Out-Null
New-Item -ItemType Directory -Path $localLogFolder -Force | Out-Null


#
# Copy only the FULL backup required for this restore.
#
$localFullPath = Join-Path $localFullFolder $full.Name

Write-Host "COPY FULL: $($full.Name)"
Copy-Item -LiteralPath $full.FullName -Destination $localFullPath -Force


#
# Copy only the LOG backups required for this restore.
#
$localLogs = @()

foreach ($sourceLog in $logs)
{
    $localLogPath = Join-Path $localLogFolder $sourceLog.Name

    Write-Host "COPY LOG:  $($sourceLog.Name)"
    Copy-Item -LiteralPath $sourceLog.FullName -Destination $localLogPath -Force

    $localLogs += Get-Item -LiteralPath $localLogPath
}


#
# Verify that every required file was copied.
#
$sourceFullLength = $full.Length
$localFullLength  = (Get-Item -LiteralPath $localFullPath).Length

if ($sourceFullLength -ne $localFullLength)
{
    throw "The local FULL backup size does not match the source file."
}

for ($i = 0; $i -lt $logs.Count; $i++)
{
    if ($logs[$i].Length -ne $localLogs[$i].Length)
    {
        throw "The local copy of $($logs[$i].Name) does not match the source file size."
    }
}


#
# Delete previous DR database.
#
$sql = @"
IF DB_ID('$db') IS NOT NULL
BEGIN
    ALTER DATABASE [$db]
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    DROP DATABASE [$db];
END
"@

Invoke-Sqlcmd `
    -ServerInstance $server `
    -Query $sql `
    -AbortOnError


#
# Get the logical file names from the backup.
#
$sql = @"
RESTORE FILELISTONLY
FROM DISK = '$localFullPath';
"@

$fileList = Invoke-Sqlcmd `
    -ServerInstance $server `
    -Query $sql `
    -AbortOnError

$dataLogical = ($fileList | Where-Object { $_.Type -eq 'D' }).LogicalName
$logLogical  = ($fileList | Where-Object { $_.Type -eq 'L' }).LogicalName

Write-Host "Data Logical Name: $dataLogical"
Write-Host "Log  Logical Name: $logLogical"


#
# Restore FULL backup and leave waiting for logs.
#
$sql = @"
RESTORE DATABASE [$db]
FROM DISK = '$localFullPath'
WITH
    MOVE '$dataLogical'
        TO '$dataPath',
    MOVE '$logLogical'
        TO '$logPath',
    NORECOVERY,
    REPLACE;
"@
Invoke-Sqlcmd `
    -ServerInstance $server `
    -Query $sql `
    -QueryTimeout 0 `
    -AbortOnError


#
# Restore all but the final transaction-log backup.
#
for ($i = 0; $i -lt $localLogs.Count - 1; $i++)
{
    $file = $localLogs[$i]

    Write-Host "LOG NORECOVERY: $($file.Name)"

    $sql = @"
RESTORE LOG [$db]
FROM DISK = '$($file.FullName)'
WITH NORECOVERY;
"@

    Invoke-Sqlcmd `
        -ServerInstance $server `
        -Query $sql `
        -QueryTimeout 0 `
        -AbortOnError
}


#
# Restore the final transaction-log backup and bring the database online.
#
$last = $localLogs[-1]

Write-Host "FINAL LOG RECOVERY: $($last.Name)"

$stopAtClause = ""

if ($PSBoundParameters.ContainsKey("RestoreTime"))
{
    $stopAtSql = $RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss")
    $stopAtClause = ", STOPAT = '$stopAtSql'"
}

$sql = @"
RESTORE LOG [$db]
FROM DISK = '$($last.FullName)'
WITH RECOVERY$stopAtClause;
"@

Invoke-Sqlcmd `
    -ServerInstance $server `
    -Query $sql `
    -QueryTimeout 0 `
    -AbortOnError


#
# Validate the restored database.
#
$sql = @"
SELECT
    name,
    state_desc
FROM sys.databases
WHERE name = '$db';
"@

Invoke-Sqlcmd `
    -ServerInstance $server `
    -Query $sql `
    -AbortOnError


Write-Host "=========================="
Write-Host "DR RESTORE COMPLETED"
Write-Host "=========================="