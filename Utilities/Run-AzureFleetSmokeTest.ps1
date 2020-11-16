##############################################################################################
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
# Run-AzureFleetSmokeTest.ps1
<#
.SYNOPSIS
    This script is to run Azure Fleet Smoke test
.PARAMETER
Documentation
.NOTES
    Creation Date:
    Purpose/Change:
.EXAMPLE
    Run-AzureFleetSmokeTest.ps1 -Location "eastus" -AzureSecretsFile "secret.yml" -TestPass "2010 PROD"
#>
###############################################################################################
Param
(
    [string] $AzureSecretsFile,
    [string] $Location,
    [string] $DbName,
    [string] $DbServer,
    [string] $TestPass
)

$StatusRunning = "Running"

Function Invoke-SmokeTest($Image, $Location)
{
    Write-Host "Info: Run smoke test for $Image in $Location"

    $logInfo = "Info: .\lisa -r runbook\smoke.yml " +
    "-v gGallery:$Image -v location:$Location -v testPass:$TestPass -v adminPrivateKeyFile:$env:LISA_PRI_SECUREFILEPATH -v dbName $dbName"
    Write-Host $logInfo

    .\lisa -r runbook\smoke.yml `
    -v gGallery:$Image -v location:$Location -v testPass:$TestPass -v dbName:$DbName -v adminPrivateKeyFile:$env:LISA_PRI_SECUREFILEPATH 
}

# Read secrets file and terminate if not present.
Write-Host "Info: Check the Azure Secrets File..."
if (![String]::IsNullOrEmpty($AzureSecretsFile) -and (Test-Path -Path $AzureSecretsFile)) {
    $content = Get-Content -Path $AzureSecretsFile
    foreach ($line in $content) {
        if ($line.split(':')[0] -eq 'dbUserName') {
            $dbuser = $line.split(':')[1].trim()
        }
        if ($line.split(':')[0] -eq 'dbPassword') {
            $dbpassword = $line.split(':')[1].trim()
        }
    }
} else {
    Write-Host "Error: Please provide value for -AzureSecretsFile"
    exit 1
}

$server = $DbServer
$database = $DbName

if (!$server -or !$dbuser -or !$dbpassword -or !$database) {
    Write-Host "Error: Database details are not provided."
    exit 1
}

$BuildId = $env:BUILD_BUILDNUMBER
$connectionString = "Server=$server;uid=$dbuser; pwd=$dbpassword;Database=$database;Encrypt=yes;" +
                    "TrustServerCertificate=no;Connection Timeout=30;MultipleActiveResultSets=True;"

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    $connection.Open()
    $sql = "
    select Image from TestPassCache 
    where Context='$BuildId' and Status='$StatusRunning'
    "
    Write-Host "Info: Run sql command: $sql"
    $dataset = new-object "System.Data.Dataset"
    $dataadapter = new-object "System.Data.SqlClient.SqlDataAdapter" ($sql, $connection)
    $null = $dataadapter.Fill($dataset)

    foreach ($row in $dataset.Tables.rows) {
        $image = $row.Image
        Invoke-SmokeTest -Image $image -Location $Location
    }

    $dataadapter.Dispose()
    $dataset.Dispose()
}
finally {
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
