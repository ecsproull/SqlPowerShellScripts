# RestoreTime format is yyyy-MM-ddTHH:mm:ss
param(
    [datetime]$RestoreTime
)

$server = ".\SQLEXPRESS"

$fullFolder = "\\wc_server\LocalSqlBackup\Accounting_live\Full"
$logFolder  = "\\wc_server\LocalSqlBackup\Accounting_live\Logs"

$db = "Accounting_test"

$dataPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\Accounting_test.mdf"
$logPath  = "C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\Accounting_test.ldf"


#
# Delete previous DR database
#
$sql = @"
IF DB_ID('$db') IS NOT NULL
BEGIN
    ALTER DATABASE [$db]
    SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    DROP DATABASE [$db];
END
"@

Invoke-Sqlcmd -ServerInstance $server -Query $sql


#
# Find FULL backup
# - If -RestoreTime is provided, use latest FULL at or before that time.
# - If omitted, use newest FULL.
#
$fullBackups = Get-ChildItem $fullFolder *.bak | Sort-Object LastWriteTime

if (-not $fullBackups)
{
    throw "No full backup files found in $fullFolder."
}

if ($PSBoundParameters.ContainsKey('RestoreTime'))
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
# Restore FULL and leave waiting for logs
#
$sql = @"
RESTORE DATABASE [$db]
FROM DISK = '$($full.FullName)'
WITH
MOVE 'Accounting_live_Data'
TO '$dataPath',

MOVE 'Accounting_live_Log'
TO '$logPath',

NORECOVERY,
REPLACE;
"@

Invoke-Sqlcmd -ServerInstance $server -Query $sql


#
# Get LOG backups after the FULL backup.
# For point-in-time restore, include logs up to the first log whose write time
# is at/after the target time, then STOPAT on that final log.
#
$allLogs = Get-ChildItem $logFolder *.trn |
           Where-Object { $_.LastWriteTime -gt $full.LastWriteTime } |
           Sort-Object LastWriteTime

if ($PSBoundParameters.ContainsKey('RestoreTime'))
{
    $cutoffLog = $allLogs |
                 Where-Object { $_.LastWriteTime -ge $RestoreTime } |
                 Select-Object -First 1

    if (-not $cutoffLog)
    {
        throw "No log backup found that reaches restore time $RestoreTime."
    }

    $logs = $allLogs |
            Where-Object { $_.LastWriteTime -le $cutoffLog.LastWriteTime }
}
else
{
    $logs = $allLogs
}


if ($logs.Count -eq 0)
{
    throw "No log files found after full backup."
}


#
# Restore all but the last log
#
for ($i = 0; $i -lt $logs.Count - 1; $i++)
{
    $file = $logs[$i]

    Write-Host "LOG NORECOVERY: $($file.Name)"

    $sql = @"
RESTORE LOG [$db]
FROM DISK = '$($file.FullName)'
WITH NORECOVERY;
"@

    Invoke-Sqlcmd -ServerInstance $server -Query $sql
}


#
# Restore final log and bring DB online
#
$last = $logs[-1]

Write-Host "FINAL LOG RECOVERY: $($last.Name)"

$stopAtClause = ""

if ($PSBoundParameters.ContainsKey('RestoreTime'))
{
    $stopAtSql = $RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss")
    $stopAtClause = ", STOPAT = '$stopAtSql'"
}

$sql = @"
RESTORE LOG [$db]
FROM DISK = '$($last.FullName)'
WITH RECOVERY$stopAtClause;
"@

Invoke-Sqlcmd -ServerInstance $server -Query $sql


#
# Simple validation
#
$sql = @"
SELECT
    name,
    state_desc
FROM sys.databases
WHERE name = '$db';
"@

Invoke-Sqlcmd -ServerInstance $server -Query $sql


Write-Host "=========================="
Write-Host "DR RESTORE COMPLETED"
Write-Host "=========================="
