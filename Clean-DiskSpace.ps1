<#
.SYNOPSIS
    A PowerShell script to clean up disk space on a Windows system with enhanced safety and discovery features.
.DESCRIPTION
    This script performs various cleanup operations to free up disk space.
    It targets temporary files, Windows Update cache, prefetch files, DNS cache,
    and offers to empty the Recycle Bin.
    It also provides guidance and an optional function to help identify large folders.
    IMPORTANT: Run this script with Administrator privileges for full functionality.
.NOTES
    Author: Gemini
    Version: 1.3
    Last Modified: 2025-05-19
.EXAMPLE
    .\Clean-DiskSpace.ps1
    (Ensure you have Administrator privileges)
#>

#Requires -RunAsAdministrator

# --- Script Configuration ---
$VerbosePreference = "Continue" # Set to "SilentlyContinue" to reduce output, "Continue" for detailed output

# --- Helper Functions ---
function Get-FreeDiskSpace {
    param (
        [string]$DriveLetter = "C"
    )
    try {
        $drive = Get-PSDrive $DriveLetter -ErrorAction Stop
        $freeSpaceBytes = $drive.Free
        $freeSpaceGB = [math]::Round($freeSpaceBytes / 1GB, 2)
        return $freeSpaceGB
    }
    catch {
        Write-Warning "Could not retrieve free space for drive $DriveLetter. $_"
        return $null
    }
}

function Test-Admin {
    # Corrected line: Using proper object creation for WindowsPrincipal from current WindowsIdentity
    $windowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentUser = New-Object System.Security.Principal.WindowsPrincipal($windowsIdentity)
    
    if (-not $currentUser.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This script needs to be run with Administrator privileges."
        Write-Warning "Please re-run PowerShell as Administrator and execute this script again."
        Write-Host "Script will exit." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        exit 1
    }
    Write-Host "Administrator privileges confirmed." -ForegroundColor Green
}

# --- Function to Show Largest Folders (Not run automatically) ---
function Show-LargestFoldersInPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ScanPath,
        [int]$TopN = 10
    )
    if (-not (Test-Path $ScanPath -PathType Container)) {
        Write-Warning "The path '$ScanPath' does not exist or is not a folder. Please provide a valid folder path."
        return
    }

    Write-Host ""
    Write-Host "--- Identifying Top $TopN Largest Subfolders in '$ScanPath' ---" -ForegroundColor Magenta
    Write-Host "This might take some time depending on the size and number of items in the path..."
    $folderSizes = @() # Array to hold folder objects with sizes

    try {
        Get-ChildItem -Path $ScanPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $folder = $_
            Write-Verbose "Calculating size for $($folder.FullName)..."
            try {
                $folderSize = (Get-ChildItem -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                $folderSizes += [PSCustomObject]@{
                    Path   = $folder.FullName
                    SizeGB = if ($folderSize) { [math]::Round($folderSize / 1GB, 2) } else { 0 }
                }
            } catch {
                Write-Warning "Could not calculate size for $($folder.FullName): $($_.Exception.Message)"
                $folderSizes += [PSCustomObject]@{ # Add with error indication
                    Path   = $folder.FullName
                    SizeGB = "Error/Access Denied"
                }
            }
        }

        # Sort and display
        if ($folderSizes.Count -gt 0) {
            $folderSizes | Sort-Object -Property @{Expression = { if ($_.SizeGB -is [double]) { $_.SizeGB } else { -1 } } } -Descending | Select-Object -First $TopN | Format-Table -AutoSize
        } else {
            Write-Host "No subfolders found or accessible in '$ScanPath'." -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "An error occurred while trying to list folders in '$ScanPath': $_"
    }
    Write-Host "Tip: You can run this function again with a different path from your PowerShell prompt, e.g.:"
    Write-Host "Show-LargestFoldersInPath -ScanPath ""C:\Users\YourUserName\Downloads"" -TopN 15"
    Write-Host ""
}


# --- Main Script ---

# Check for Administrator Privileges
Test-Admin

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   Windows Disk Cleanup Script" -ForegroundColor Cyan
Write-Host "========================================="
Write-Host ""

# --- SAFETY INFORMATION ---
Write-Host "IMPORTANT SAFETY INFORMATION:" -ForegroundColor Red
Write-Host "--------------------------------------------------------------------------------"
Write-Host "This script is designed to clean common temporary locations and caches."
Write-Host "It WILL NOT delete your personal files in folders like:" -ForegroundColor Yellow
Write-Host "  - Documents, Desktop, Pictures, Videos, Music"
Write-Host "  - By default, it WILL NOT touch your Downloads folder (though it's a good place to check manually!)."
Write-Host "It WILL NOT uninstall your applications (only some temporary cache files related to them)."
Write-Host ""
Write-Host "The script WILL target:" -ForegroundColor Green
Write-Host "  - Windows Temporary Files (C:\Windows\Temp)"
Write-Host "  - User Temporary Files (%TEMP%)"
Write-Host "  - Windows Update Cleanup (using DISM - Component Store)"
Write-Host "  - Prefetch Files (C:\Windows\Prefetch)"
Write-Host "  - DNS Cache"
Write-Host "  - Optionally, the Recycle Bin (you will be asked for confirmation)."
Write-Host "--------------------------------------------------------------------------------"
Write-Host "Always review scripts from any source if you are unsure."
Write-Host "Ensure all important work is saved before proceeding."
Write-Host ""
Read-Host "Press Enter to continue if you understand and agree, or Ctrl+C to exit." | Out-Null
Write-Host ""


# Get initial disk space
$initialFreeSpace = Get-FreeDiskSpace -DriveLetter "C"
if ($null -ne $initialFreeSpace) {
    Write-Host "Initial free disk space on C: drive: $($initialFreeSpace) GB" -ForegroundColor Green
} else {
    Write-Warning "Could not determine initial free disk space. Proceeding with cleanup..."
}
Write-Host ""

# --- Cleanup Operations ---

# 1. Clean Windows Temporary Files
Write-Host "--- Cleaning Windows Temporary Files (C:\Windows\Temp) ---" -ForegroundColor Yellow
Write-Host "These are generally safe to delete."
$winTempPath = "C:\Windows\Temp\*"
try {
    Remove-Item -Path $winTempPath -Recurse -Force -ErrorAction SilentlyContinue -Verbose:$false
    Write-Host "Windows temporary files cleaned." -ForegroundColor Green
}
catch {
    Write-Warning "Could not clean all Windows temporary files. Some files might be in use. $_"
}
Write-Host ""

# 2. Clean User Temporary Files
Write-Host "--- Cleaning User Temporary Files (%TEMP%) ---" -ForegroundColor Yellow
Write-Host "These are generally safe to delete."
$userTempPath = "$env:TEMP\*"
try {
    Remove-Item -Path $userTempPath -Recurse -Force -ErrorAction SilentlyContinue -Verbose:$false
    Write-Host "User temporary files cleaned." -ForegroundColor Green
}
catch {
    Write-Warning "Could not clean all user temporary files. Some files might be in use. $_"
}
Write-Host ""

# 3. Windows Update Cleanup (DISM Component Store Cleanup)
Write-Host "--- Running Windows Update Cleanup (DISM) ---" -ForegroundColor Yellow
Write-Host "This process cleans up unneeded system files from Windows Update. It might take a while. Please be patient."
try {
    Write-Host "Running DISM /Online /Cleanup-Image /StartComponentCleanup..."
    DISM.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet
    Write-Host "DISM /StartComponentCleanup completed." -ForegroundColor Green
}
catch {
    Write-Warning "An error occurred during DISM cleanup: $_"
}
Write-Host ""

# 4. Clean Prefetch Files
Write-Host "--- Cleaning Prefetch Files (C:\Windows\Prefetch) ---" -ForegroundColor Yellow
Write-Host "Prefetch files are used by Windows to speed up application startup. They will be regenerated as needed."
$prefetchPath = "C:\Windows\Prefetch\*"
$prefetchEnabled = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnablePrefetcher" -ErrorAction SilentlyContinue
if ($prefetchEnabled -and $prefetchEnabled.EnablePrefetcher -ne 0) {
    try {
        Remove-Item -Path $prefetchPath -Recurse -Force -ErrorAction SilentlyContinue -Verbose:$false
        Write-Host "Prefetch files cleaned." -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not clean Prefetch files. $_"
    }
} else {
    Write-Host "Prefetch seems to be disabled or folder not accessible. Skipping." -ForegroundColor Cyan
}
Write-Host ""

# 5. Clear DNS Cache
Write-Host "--- Clearing DNS Cache ---" -ForegroundColor Yellow
try {
    Clear-DnsClientCache
    Write-Host "DNS cache cleared." -ForegroundColor Green
}
catch {
    Write-Warning "Could not clear DNS cache. $_"
}
Write-Host ""

# 6. Empty Recycle Bin
Write-Host "--- Emptying Recycle Bin ---" -ForegroundColor Yellow
$choiceRecycleBin = Read-Host "Do you want to empty the Recycle Bin for all users? This is PERMANENT. (y/n)"
if ($choiceRecycleBin -eq 'y') {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "Recycle Bin emptied." -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not empty the Recycle Bin. $_"
    }
}
else {
    Write-Host "Recycle Bin not emptied."
}
Write-Host ""

# --- Post-Cleanup ---
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   Cleanup Summary" -ForegroundColor Cyan
Write-Host "========================================="

$finalFreeSpace = Get-FreeDiskSpace -DriveLetter "C"
if ($null -ne $finalFreeSpace) {
    Write-Host "Final free disk space on C: drive: $($finalFreeSpace) GB" -ForegroundColor Green
    if ($null -ne $initialFreeSpace) {
        $spaceRecovered = [math]::Round($finalFreeSpace - $initialFreeSpace, 2)
        if ($spaceRecovered -gt 0) {
            Write-Host "Total space recovered by this script: $($spaceRecovered) GB" -ForegroundColor Green
        } elseif ($spaceRecovered -lt 0) {
             Write-Host "Disk space decreased by $([math]::Abs($spaceRecovered)) GB. This can happen if background processes wrote data during script execution." -ForegroundColor Yellow
        }
        else {
            Write-Host "No significant disk space change detected from automated cleanup." -ForegroundColor Cyan
        }
    }
} else {
    Write-Warning "Could not determine final free disk space."
}
Write-Host ""

# --- Identifying Further Unnecessary Storage Space ---
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host "   Identifying Other Large Space Consumers (Manual Steps)" -ForegroundColor Magenta
Write-Host "========================================================"
Write-Host ""
Write-Host "To find more areas where disk space is used, consider these steps:"
Write-Host ""
Write-Host "1. Use Windows Storage Settings (Recommended):" -ForegroundColor Yellow
Write-Host "   - Go to Settings > System > Storage."
Write-Host "   - This tool shows a breakdown of what's using space and offers cleanup recommendations (like 'Temporary files')."
Write-Host "   - Check 'Storage Sense' settings to automate some cleanup."
Write-Host ""

# Check for Windows.old folder
$windowsOldPath = "C:\Windows.old"
if (Test-Path $windowsOldPath) {
    Write-Host "2. Windows.old Folder Detected:" -ForegroundColor Yellow
    Write-Host "   - A 'C:\Windows.old' folder was found ($([math]::Round((Get-Item $windowsOldPath | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1GB, 2)) GB)."
    Write-Host "     This folder contains files from a previous Windows installation."
    Write-Host "   - Windows typically auto-deletes this after ~10 days. If older, or you don't need to roll back, remove it via:"
    Write-Host "     a) Settings > System > Storage > Temporary files > Select 'Previous Windows installation(s)'."
    Write-Host "     b) Disk Cleanup tool (search 'Disk Cleanup', run as admin), select 'Previous Windows installation(s)'."
    Write-Host "   - This script WILL NOT automatically delete C:\Windows.old."
    Write-Host ""
}

Write-Host "3. Manually Check Common Large File Locations:" -ForegroundColor Yellow
Write-Host "   - Downloads folder: Often contains old installers or large archives."
Write-Host "     (Path: $env:USERPROFILE\Downloads)"
Write-Host "   - Documents, Videos, Pictures: Check for very large files or old project folders you no longer need."
Write-Host ""

Write-Host "4. Use the 'Show-LargestFoldersInPath' function (Optional PowerShell Command):" -ForegroundColor Yellow
Write-Host "   The script has defined a function called 'Show-LargestFoldersInPath'."
Write-Host "   After this script finishes, you can run it in THIS PowerShell window to find large folders within a specific path."
Write-Host "   For example, to find the 10 largest folders in your Downloads directory, type:"
Write-Host "   Show-LargestFoldersInPath -ScanPath ""$env:USERPROFILE\Downloads"" -TopN 10" # Example with escaped quotes for clarity
Write-Host "   Or for your C:\Program Files directory:"
Write-Host "   Show-LargestFoldersInPath -ScanPath ""C:\Program Files"" -TopN 10" # Example with escaped quotes
Write-Host "   (Note: Scanning very large, broad paths like 'C:\' can be slow.)"
Write-Host ""

Write-Host "5. For Software Developers (Manual Commands):" -ForegroundColor Yellow
Write-Host "   Consider cleaning caches for your development tools (run these in PowerShell/Terminal):"
# Corrected lines for developer command suggestions:
Write-Host "   - NuGet cache: Consider running: dotnet nuget locals all --clear  OR  nuget locals all -clear"
Write-Host "   - npm cache: Consider running: npm cache clean --force"
Write-Host "   - pip cache: Consider running: pip cache purge"
Write-Host "   - Docker prune: Consider running: docker system prune -a --volumes  (CAUTION: This removes ALL unused images, containers, networks, and volumes. Use with care.)"
Write-Host "   - Old build artifacts in project directories (e.g., 'bin', 'obj', 'dist', 'target' folders)." # This line should now be fine.
Write-Host ""

Write-Host "Disk cleanup script finished." -ForegroundColor Green
Write-Host "It's often a good idea to restart your computer after extensive cleanup operations." # This line should also be fine.
