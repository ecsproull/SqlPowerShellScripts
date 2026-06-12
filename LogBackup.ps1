$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$file = "\\wc_server\LocalSqlBackup\Accounting_live\Logs\Accounting_live_LOG_$timestamp.trn"

$sql = @"
BACKUP LOG Accounting_live
TO DISK = '$file'
WITH CHECKSUM;
"@

Invoke-Sqlcmd -ServerInstance ".\SQLEXPRESS" `
              -Query $sql