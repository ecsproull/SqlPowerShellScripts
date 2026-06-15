$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$localPath = "C:\LocalSqlBackup\Accounting_live\Logs"
$localFile = "$localPath\Accounting_live_LOG_$timestamp.trn"

# Make sure local folder exists
New-Item -ItemType Directory -Path $localPath -Force | Out-Null

$sql = @"
BACKUP LOG Accounting_live
TO DISK = '$localFile'
WITH CHECKSUM;
"@

Invoke-Sqlcmd -ServerInstance ".\SQLEXPRESS" `
              -Query $sql

# Copy to external drive
robocopy `
    "C:\LocalSqlBackup\Accounting_live\Logs" `
    "D:\LocalSqlBackup\Accounting_live\Logs" `
    *.trn /XO /R:3 /W:5

# Copy to wc_server
robocopy `
    "C:\LocalSqlBackup\Accounting_live\Logs" `
    "\\wc_server\LocalSqlBackup\Accounting_live\Logs" `
    *.trn /XO /R:3 /W:5

# Copy to treasurer_pc
robocopy `
    "C:\LocalSqlBackup\Accounting_live\Logs" `
    "\\TREASURERS_PC\LocalSqlBackup\Accounting_live\Logs" `
    *.trn /XO /R:3 /W:5