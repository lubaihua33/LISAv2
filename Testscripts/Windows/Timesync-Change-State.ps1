# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Description
    This test will check the time sync of guest OS with the host.
    It will save/pause the VM, wait for 10 mins, resume/start the VM
    and re-check the time sync.
#>

param([string] $TestParams, [object] $AllVMData)

# Main script body
function Main {
    param (
        $VMName,
        $HvServer,
        $Ipv4,
        $VMPort,
        $VMUserName,
        $VMPassword,
        $RootDir
    )
    $testDelay = 600
    $chrony_state = $null

    # Parse the TestParams string
    $params = $TestParams.Split(";")
    foreach ($p in $params) {
        $tokens = $p.Trim().Split("=")
        if ($tokens.Length -ne 2) {
            continue
        }

        $val = $tokens[1].Trim()
        switch ($tokens[0].Trim().ToLower()) {
            "vmState" {$vmState = $val.toLower()}
            "testdelay" {$testDelay = $val}
            "chrony" {$chrony_state = $val}
            default { continue }
        }
    }
    if (-not $vmState) {
        Write-LogErr "testParams is missing the vmState parameter"
        return "FAIL"
    }
    Write-LogInfo "testDelay = $testDelay; chrony_state = $chrony_state;"

    # Change the working directory
    if (-not (Test-Path $RootDir)) {
        Write-LogErr "The directory `"${RootDir}`" does not exist"
        return "FAIL"
    }
    Set-Location $RootDir

    # Config TimeSync on the guest VM
    $retVal = Optimize-TimeSync -Ipv4 $Ipv4 -Port $VMPort -Username $VMUserName `
                -Password $VMPassword
    if (-not $retVal) {
        Write-LogErr "Failed to config time sync."
        return "FAIL"
    }

    # Get times for host & guest
    $diffInSeconds = Get-TimeSync -Ipv4 $Ipv4 -Port $VMPort `
         -Username $VMUserName -Password $VMPassword
    if ($diffInSeconds -and $diffInSeconds -lt 5) {
        Write-LogInfo "Time is properly synced"
    } else {
        Write-LogErr "Time is out of sync before pause/save action!"
        return "FAIL"
    }

    if ($chrony_state -eq "off") {
        Write-LogInfo "Chrony has been turned off by shell script."
    }

    Start-Sleep -Seconds 10
    # Pause/Save the VM state and wait for 10 mins.
    if ($vmState -eq "pause") {
        Suspend-VM -Name $VMName -ComputerName $HvServer -Confirm:$False
    } elseif ($vmState -eq "save") {
        Save-VM -Name $VMName -ComputerName $HvServer -Confirm:$False
    } else {
        Write-LogErr "Invalid VM state - ${vmState}"
    }

    if ($? -ne $true) {
      Write-LogErr "Error while suspending the VM state"
      return "FAIL"
    }

    # If the test delay was specified, sleep for a bit
    Write-LogInfo "Sleeping for ${testDelay} seconds"
    Start-Sleep -Seconds $testDelay

    # After 10 mins resume the VM and check the time sync.
    Start-VM -Name $VMName -ComputerName $HvServer -Confirm:$False `
        -WarningAction SilentlyContinue
    if ($? -ne "True") {
      Write-LogErr "Error while changing VM state"
      return "FAIL"
    }

    # Get times for host & guest
    $diffInSeconds = Get-TimeSync -Ipv4 $Ipv4 -Port $VMPort `
         -Username $VMUserName -Password $VMPassword
    if ($diffInSeconds -and $diffInSeconds -lt 5) {
        Write-LogInfo "Time is properly synced after start action"
        return "PASS"
    } else {
        Write-LogErr "Time is out of sync after start action!"
        return "FAIL"
    }
}

Main -VMName $AllVMData.RoleName -HvServer $GlobalConfig.Global.Hyperv.Hosts.ChildNodes[0].ServerName `
         -Ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
         -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory
