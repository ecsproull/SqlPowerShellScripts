$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$localPath = "C:\LocalSqlBackup\Accounting_live\Full"
$localFile = "$localPath\Accounting_live_FULL_$timestamp.bak"

# Make sure local folder exists
New-Item -ItemType Directory -Path $localPath -Force | Out-Null

$sql = @"
BACKUP DATABASE Accounting_live
TO DISK = '$localFile'
WITH CHECKSUM;
"@

Invoke-Sqlcmd -ServerInstance ".\SQLEXPRESS" `
              -Query $sql

# Copy to machine B
robocopy `
    "C:\LocalSqlBackup\Accounting_live\Full" `
    "D:\LocalSqlBackup\Accounting_live\Full" `
    *.bak /XO /R:3 /W:5

# Copy to wc_server
robocopy `
    "C:\LocalSqlBackup\Accounting_live\Full" `
    "\\wc_server\LocalSqlBackup\Accounting_live\Full" `
    *.bak /XO /R:3 /W:5


# Copy to treasurer_pc
robocopy `
    "C:\LocalSqlBackup\Accounting_live\Full" `
    "\\TREASURERS_PC\LocalSqlBackup\Accounting_live\Full" `
    *.bak /XO /R:3 /W:5