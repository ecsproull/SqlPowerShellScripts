$backupFolder = "\\WCSERVER2\Users\presi\OneDrive\SqlBackup"
$mysqlExe     = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"

$dbUser = "woodtest_import"
$dbPass = "woodclub.import12#"

# Find latest matching backup
$latestBackup = Get-ChildItem -Path $backupFolder -Filter "wpdb-i2509778_wp1*.sql" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latestBackup) {
    throw "No matching backup file found in $backupFolder"
}

Write-Host "Using backup file: $($latestBackup.FullName)"
Write-Host "Importing database..."

# Import the SQL file directly
$output = & $mysqlExe `
    --host=127.0.0.1 `
    --user=$dbUser `
    --password=$dbPass `
    i2509778_wp1 `
    --execute="source $($latestBackup.FullName)" 2>&1

# Display any output from MySQL
if ($output) {
    $output
}

if ($LASTEXITCODE -ne 0) {
    throw "MySQL import failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "=========================="
Write-Host "IMPORT COMPLETED"
Write-Host "=========================="
