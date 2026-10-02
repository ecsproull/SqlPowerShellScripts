<#
.SYNOPSIS
  Runs the account 47 credit query against Accounting_live and emails a one-line result via SendGrid.

.NOTES
  Reads the SendGrid API key from the 'SendGrid' environment variable.
#>

$ErrorActionPreference = 'Stop'

# ---- Config -----------------------------------------------------------------
$SqlInstance = 'localhost\SQLEXPRESS'            # e.g. 'localhost\SQLEXPRESS' for a named instance
$Database    = 'Accounting_live'
$From        = 'classes@scwwoodshop.com'   # must be on your SendGrid-authenticated domain
$To          = @(
    'ecsproull765@gmail.com'
    'SCWWoodshopguy@gmail.com'
)
$Subject     = 'Picnic Attendance Report'

$Query = @'
SELECT SUM(credit_amount) / 5
  FROM [Accounting_live].[ledger].[ledger_entries]
  WHERE account_id = 47
'@

# ---- Query ------------------------------------------------------------------
$connStr = "Server=$SqlInstance;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$conn = New-Object System.Data.SqlClient.SqlConnection $connStr
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $result = $cmd.ExecuteScalar()
}
finally {
    $conn.Dispose()
}

if ($result -is [System.DBNull] -or $null -eq $result) { $result = 0 }
$value = '{0:F0}' -f [decimal]$result

# ---- Email via SendGrid v3 API ---------------------------------------------
$apiKey = $env:SendGrid
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable('SendGrid', 'Machine') }
if (-not $apiKey) { throw "SendGrid environment variable not found" }

$body = @{
    personalizations = @(@{ to = @($To | ForEach-Object { @{ email = $_ } }) })
    from             = @{ email = $From }
    subject          = $Subject
    content          = @(@{ type = 'text/plain'; value = "Current Paid attendance is $value as of $(Get-Date -Format 'yyyy-MM-dd HH:mm')." })
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Method Post -Uri 'https://api.sendgrid.com/v3/mail/send' `
    -Headers @{ Authorization = "Bearer $apiKey" } `
    -ContentType 'application/json' -Body $body

Write-Output "Sent: $value"