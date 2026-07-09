$backupFolder = "C:\Users\presi\OneDrive\SqlBackup"
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

# Create a modified temp copy
$tempSql = Join-Path $env:TEMP "woodtest-import.sql"

(Get-Content $latestBackup.FullName -Raw) `
    -replace 'i2509778_wp1', 'wordpress' |
    Set-Content $tempSql -Encoding UTF8

Write-Host "Importing modified SQL file..."

# Run the SQL file
& $mysqlExe `
    --host=127.0.0.1 `
    --user=$dbUser `
    --password=$dbPass `
    wordpress `
    --execute="source $tempSql"

if ($LASTEXITCODE -ne 0) {
    throw "MySQL import failed with exit code $LASTEXITCODE"
}

Write-Host "Database import completed."

ssh scw-wc-linux@192.168.8.105 "cd /var/www/wordpress/wp-content/plugins/SignUps/scripts && ./keyimport.sh woodtest"

Write-Host "DB updated from Wordpress"