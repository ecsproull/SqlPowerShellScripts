$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$file = "\\wc_server\LocalSqlBackup\Accounting_live\Full\Accounting_live_FULL_$timestamp.bak"

$sql = @"
BACKUP DATABASE Accounting_live
TO DISK = '$file'
WITH CHECKSUM;
"@

Invoke-Sqlcmd -ServerInstance ".\SQLEXPRESS" `
              -Query $sql