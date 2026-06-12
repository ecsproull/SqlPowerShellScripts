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
# Find newest full backup
#
$full = Get-ChildItem $fullFolder *.bak |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

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
# Get all logs after the FULL backup
#
$logs = Get-ChildItem $logFolder *.trn |
        Where-Object { $_.LastWriteTime -gt $full.LastWriteTime } |
        Sort-Object LastWriteTime


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

$sql = @"
RESTORE LOG [$db]
FROM DISK = '$($last.FullName)'
WITH RECOVERY;
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
