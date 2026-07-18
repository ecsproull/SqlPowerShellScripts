$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$localPath = "C:\LocalSqlBackup\WoodClub\Logs"
$localFile = "$localPath\WoodClub_LOG_$timestamp.trn"

# Make sure local folder exists
New-Item -ItemType Directory -Path $localPath -Force | Out-Null

$sql = @"
BACKUP LOG WoodClub
TO DISK = '$localFile'
WITH CHECKSUM;
"@

Invoke-Sqlcmd -ServerInstance ".\SQLEXPRESS" `
              -Query $sql

# Copy to external drive
robocopy `
    "C:\LocalSqlBackup\WoodClub\Logs" `
    "D:\LocalSqlBackup\WoodClub\Logs" `
    *.trn /XO /R:3 /W:5

# Copy to wc_server
robocopy `
    "C:\LocalSqlBackup\WoodClub\Logs" `
    "\\wc_server\LocalSqlBackup\WoodClub\Logs" `
    *.trn /XO /R:3 /W:5

# Copy to treasurer_pc
robocopy `
    "C:\LocalSqlBackup\WoodClub\Logs" `
    "\\TREASURERS_PC\LocalSqlBackup\WoodClub\Logs" `
    *.trn /XO /R:3 /W:5