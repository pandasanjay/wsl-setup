<#
.SYNOPSIS
    Monitors Windows system performance with enhanced metrics and provides intelligent analysis to diagnose sluggishness.
    It collects system-wide CPU, Memory, Disk I/O & Latency, GPU, Network, and Temperature,
    and identifies top processes by CPU, Memory, and Disk I/O.

.DESCRIPTION
    This script runs for a specified duration, collecting detailed performance metrics at regular intervals.
    It outputs the data to a CSV file and then runs a smart analysis function to interpret the data,
    flagging potential bottlenecks and providing actionable insights directly in the console.

.NOTES
    Author: Your AI Assistant
    Version: 2.0
    Date: July 2, 2025
    Requires: PowerShell 5.1 or later (built into Windows 10/11). Run as Administrator for best results.

.PARAMETER LogFile
    Path to the CSV file where performance data will be logged.
.PARAMETER MonitorIntervalSeconds
    The interval (in seconds) between each data collection point.
.PARAMETER DurationMinutes
    The total duration (in minutes) for which the monitoring will run.
.PARAMETER TopProcessesCount
    The number of top processes (by CPU, Memory, and I/O) to log in each interval.
#>

# --- Configuration Parameters ---
$LogFile = "windows_performance_log_smart.csv"
$MonitorIntervalSeconds = 5 # How often to collect data (e.g., every 5 seconds)
$DurationMinutes = 15       # How long to monitor (e.g., 15 minutes)
$TopProcessesCount = 5      # Number of top processes to log by CPU, Memory, and I/O

# --- Function to get system-wide metrics ---
function Get-SystemMetrics {
    param()

    # Get CPU usage and related metrics
    $cpu = Get-Counter '\Processor(_Total)\% Processor Time' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
    $dpcTime = Get-Counter '\Processor(_Total)\% DPC Time' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
    $interrupts = Get-Counter '\Processor(_Total)\Interrupts/sec' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue

    # Get Memory usage
    $memory = Get-Counter '\Memory\% Committed Bytes In Use' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
    $memoryTotalBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $memoryUsedBytes = $memoryTotalBytes * ($memory / 100)
    $pageFileUsage = Get-Counter '\Paging File(_Total)\% Usage' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue

    # Get Disk I/O and *Latency* (crucial for sluggishness)
    $diskReadBytes = (Get-Counter '\LogicalDisk(*)\Disk Read Bytes/sec' | Where-Object {$_.InstanceName -ne "_Total"} | Select-Object -ExpandProperty CounterSamples).CookedValue | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $diskWriteBytes = (Get-Counter '\LogicalDisk(*)\Disk Write Bytes/sec' | Where-Object {$_.InstanceName -ne "_Total"} | Select-Object -ExpandProperty CounterSamples).CookedValue | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $diskQueueLength = (Get-Counter '\LogicalDisk(_Total)\Current Disk Queue Length').CounterSamples.CookedValue
    $diskReadLatency = (Get-Counter '\LogicalDisk(_Total)\Avg. Disk sec/Read').CounterSamples.CookedValue * 1000 # Convert to ms
    $diskWriteLatency = (Get-Counter '\LogicalDisk(_Total)\Avg. Disk sec/Write').CounterSamples.CookedValue * 1000 # Convert to ms

    # Get Network I/O
    $networkSent = (Get-Counter '\Network Interface(*)\Bytes Sent/sec' | Select-Object -ExpandProperty CounterSamples).CookedValue | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $networkReceived = (Get-Counter '\Network Interface(*)\Bytes Received/sec' | Select-Object -ExpandProperty CounterSamples).CookedValue | Measure-Object -Sum | Select-Object -ExpandProperty Sum

    # Get System Uptime
    $uptimeSeconds = (Get-Counter '\System\System Up Time').CounterSamples.CookedValue
    $uptime = New-TimeSpan -Seconds $uptimeSeconds

    # Get Temperature (in Celsius)
    $temperatureCelsius = "N/A"
    try {
        $tempData = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue
        if ($tempData) {
            # Average the temperatures from all thermal zones
            $avgKelvinTenths = ($tempData | Measure-Object -Property CurrentTemperature -Average).Average
            $temperatureCelsius = [math]::Round(($avgKelvinTenths / 10) - 273.15, 2)
        }
    }
    catch {
        Write-Warning "Could not retrieve temperature via WMI/CIM. Ensure you are running as Administrator. Error: $($_.Exception.Message)"
    }

    # Get GPU Usage (requires Windows 10 Fall Creators Update or newer)
    $gpuUsage = "N/A"
    try {
        # This counter aggregates usage across all GPU engines (3D, Copy, Video Decode, etc.)
        $gpuCounters = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
        if ($gpuCounters) {
            # Summing up all engines can exceed 100% if multiple engines are used. We find the max utilization of any single engine.
            $gpuUsage = ($gpuCounters.CounterSamples.CookedValue | Measure-Object -Maximum).Maximum
        }
    }
    catch {
        Write-Warning "Could not retrieve GPU counters. This may not be supported on your system or requires running as Administrator."
    }

    [PSCustomObject]@{
        Timestamp                  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        CpuPercent                 = [math]::Round($cpu, 2)
        MemoryTotalGB              = [math]::Round($memoryTotalBytes / 1GB, 2)
        MemoryUsedGB               = [math]::Round($memoryUsedBytes / 1GB, 2)
        MemoryPercent              = [math]::Round($memory, 2)
        PageFileUsagePercent       = [math]::Round($pageFileUsage, 2)
        DiskReadMBps               = [math]::Round($diskReadBytes / 1MB, 2)
        DiskWriteMBps              = [math]::Round($diskWriteBytes / 1MB, 2)
        DiskQueueLength            = [math]::Round($diskQueueLength, 2)
        DiskReadLatencyMs          = [math]::Round($diskReadLatency, 2)
        DiskWriteLatencyMs         = [math]::Round($diskWriteLatency, 2)
        NetworkSentMBps            = [math]::Round($networkSent / 1MB, 2)
        NetworkReceivedMBps        = [math]::Round($networkReceived / 1MB, 2)
        GpuUsagePercent            = if ($gpuUsage -ne "N/A") { [math]::Round($gpuUsage, 2) } else { "N/A" }
        TemperatureCelsius         = $temperatureCelsius
        DpcTimePercent             = [math]::Round($dpcTime, 2)
        InterruptsPerSec           = [math]::Round($interrupts, 0)
        SystemUptime               = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
    }
}

# --- Function to get top processes by various metrics ---
function Get-TopProcesses {
    param(
        [int]$Count
    )

    $processes = @()
    try {
        # Get all process data in one go for efficiency
        $processes = Get-Process -IncludeUserName -ErrorAction Stop | Where-Object { $_.Name -ne "Idle" }
    }
    catch {
        Write-Warning "Failed to retrieve processes with Get-Process: $($_.Exception.Message)"
        return @{}
    }

    # Sort by CPU, Memory, and create a placeholder for I/O
    $topCpu = $processes | Sort-Object -Property CPU -Descending | Select-Object -First $Count
    $topMem = $processes | Sort-Object -Property WorkingSet -Descending | Select-Object -First $Count

    # Get I/O data separately as it's more expensive
    $ioData = @{}
    $ioProcesses = Get-Counter '\Process(*)\IO Data Bytes/sec' -ErrorAction SilentlyContinue | Group-Object -Property InstanceName
    if ($ioProcesses) {
        foreach ($procGroup in $ioProcesses) {
            $procName = $procGroup.Name
            if ($procName -eq "_Total" -or $procName -eq "Idle") { continue }
            $totalIo = ($procGroup.Group.CookedValue | Measure-Object -Sum).Sum
            $ioData[$procName] = $totalIo
        }
    }
    $topIo = $ioData.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First $Count


    # Format the results into a flat hashtable for the CSV
    $result = @{}
    for ($i = 0; $i -lt $topCpu.Count; $i++) {
        $p = $topCpu[$i]
        $result["TopCpuProc$($i+1)Name"] = $p.Name
        $result["TopCpuProc$($i+1)Cpu"] = [math]::Round($p.CPU, 2)
        $result["TopCpuProc$($i+1)MemMB"] = [math]::Round($p.WorkingSet / 1MB, 2)
        $result["TopCpuProc$($i+1)User"] = $p.UserName
    }

    for ($i = 0; $i -lt $topMem.Count; $i++) {
        $p = $topMem[$i]
        $result["TopMemProc$($i+1)Name"] = $p.Name
        $result["TopMemProc$($i+1)Cpu"] = [math]::Round($p.CPU, 2)
        $result["TopMemProc$($i+1)MemMB"] = [math]::Round($p.WorkingSet / 1MB, 2)
        $result["TopMemProc$($i+1)User"] = $p.UserName
    }

    for ($i = 0; $i -lt $topIo.Count; $i++) {
        $p = $topIo[$i]
        $result["TopIoProc$($i+1)Name"] = $p.Name
        $result["TopIoProc$($i+1)IoMBps"] = [math]::Round($p.Value / 1MB, 2)
    }

    return $result
}

# --- Main Monitoring Logic ---
function Start-PerformanceMonitoring {
    param(
        [string]$LogFile,
        [int]$MonitorIntervalSeconds,
        [int]$DurationMinutes,
        [int]$TopProcessesCount
    )

    $numIterations = [int](($DurationMinutes * 60) / $MonitorIntervalSeconds)
    Write-Host "Starting performance monitoring for $DurationMinutes minutes. Press Ctrl+C to stop early." -ForegroundColor Green
    Write-Host "Data will be logged to '$LogFile'"

    $headers = @(
        "Timestamp", "CpuPercent", "MemoryTotalGB", "MemoryUsedGB", "MemoryPercent", "PageFileUsagePercent",
        "DiskReadMBps", "DiskWriteMBps", "DiskQueueLength", "DiskReadLatencyMs", "DiskWriteLatencyMs",
        "NetworkSentMBps", "NetworkReceivedMBps", "GpuUsagePercent", "TemperatureCelsius",
        "DpcTimePercent", "InterruptsPerSec", "SystemUptime"
    )
    for ($i = 1; $i -le $TopProcessesCount; $i++) {
        $headers += "TopCpuProc${i}Name", "TopCpuProc${i}Cpu", "TopCpuProc${i}MemMB", "TopCpuProc${i}User"
    }
    for ($i = 1; $i -le $TopProcessesCount; $i++) {
        $headers += "TopMemProc${i}Name", "TopMemProc${i}Cpu", "TopMemProc${i}MemMB", "TopMemProc${i}User"
    }
    for ($i = 1; $i -le $TopProcessesCount; $i++) {
        $headers += "TopIoProc${i}Name", "TopIoProc${i}IoMBps"
    }

    # Write CSV header, overwriting any existing file
    $headers -join "," | Out-File -FilePath $LogFile -Encoding UTF8

    $allData = for ($i = 1; $i -le $numIterations; $i++) {
        $progress = [int](($i / $numIterations) * 100)
        Write-Progress -Activity "Monitoring System Performance" -Status "$progress% Complete" -PercentComplete $progress

        $systemMetrics = Get-SystemMetrics
        $topProcesses = Get-TopProcesses -Count $TopProcessesCount

        $row = New-Object PSCustomObject
        $systemMetrics.PSObject.Properties | ForEach-Object { $row | Add-Member -MemberType NoteProperty -Name $_.Name -Value $_.Value }
        $topProcesses.Keys | ForEach-Object { $row | Add-Member -MemberType NoteProperty -Name $_ -Value $topProcesses[$_] }

        # Create a consistent row for the CSV file
        $outputRow = $headers | ForEach-Object {
            $value = $row.$_
            # Enclose in quotes if it contains a comma
            if ($value -like '*,*') { "`"$value`"" } else { $value }
        }

        $outputRow -join "," | Out-File -FilePath $LogFile -Encoding UTF8 -Append
        Write-Host "[$($i)/$numIterations] Logged data point at $($systemMetrics.Timestamp)"
        
        # Output the object for live analysis later
        $row

        Start-Sleep -Seconds $MonitorIntervalSeconds
    }

    Write-Progress -Activity "Monitoring System Performance" -Completed
    Write-Host "Monitoring complete. Data saved to '$LogFile'" -ForegroundColor Green
    return $allData
}

# --- Smart Analysis Function ---
function Analyze-PerformanceLog {
    param(
        [Parameter(Mandatory=$true)]
        [psobject[]]$Data,
        [string]$LogFile,
        [int]$TopProcessesCount
    )

    Write-Host "`n--- Smart Analysis of Performance Log ---" -ForegroundColor Cyan

    if (-not $Data) {
        Write-Host "No data available for analysis." -ForegroundColor Yellow
        return
    }

    # --- Define Thresholds for "Sluggishness" ---
    $thresholds = @{
        CpuPercent         = 90 # Sustained CPU above 90%
        MemoryPercent      = 90 # Memory usage above 90%
        DiskQueueLength    = 2  # Queue length > 2 can indicate a bottleneck
        DiskReadLatencyMs  = 50 # > 50ms latency is noticeable
        DiskWriteLatencyMs = 50 # > 50ms latency is noticeable
        GpuUsagePercent    = 90 # GPU maxed out
        TemperatureCelsius = 85 # High temps can cause thermal throttling
        DpcTimePercent     = 15 # High DPC time can indicate driver issues
    }

    # --- Overall Averages and Maxima ---
    Write-Host "`n[1] Overall System Performance Summary:" -ForegroundColor White
    $avgCpu = ($Data.CpuPercent | Measure-Object -Average).Average
    $maxCpu = ($Data.CpuPercent | Measure-Object -Maximum).Maximum
    $avgMem = ($Data.MemoryPercent | Measure-Object -Average).Average
    $maxMem = ($Data.MemoryPercent | Measure-Object -Maximum).Maximum
    $maxDiskQueue = ($Data.DiskQueueLength | Measure-Object -Maximum).Maximum
    $maxReadLatency = ($Data.DiskReadLatencyMs | Measure-Object -Maximum).Maximum
    $maxWriteLatency = ($Data.DiskWriteLatencyMs | Measure-Object -Maximum).Maximum
    $maxTemp = ($Data.TemperatureCelsius -ne 'N/A' | ForEach-Object { [double]$_ } | Measure-Object -Maximum).Maximum
    $maxGpu = ($Data.GpuUsagePercent -ne 'N/A' | ForEach-Object { [double]$_ } | Measure-Object -Maximum).Maximum


    Write-Host "  - CPU Usage:      Avg $([math]::Round($avgCpu,1))%, Max $([math]::Round($maxCpu,1))%"
    Write-Host "  - Memory Usage:   Avg $([math]::Round($avgMem,1))%, Max $([math]::Round($maxMem,1))%"
    Write-Host "  - Disk Latency:   Max Read $([math]::Round($maxReadLatency,1)) ms, Max Write $([math]::Round($maxWriteLatency,1)) ms"
    Write-Host "  - Disk Queue:     Max Length $([math]::Round($maxDiskQueue,1))"
    if ($maxGpu) { Write-Host "  - GPU Usage:      Max $([math]::Round($maxGpu,1))%" }
    if ($maxTemp) { Write-Host "  - Temperature:    Max $([math]::Round($maxTemp,1))°C" }
    Write-Host "  - System Uptime:  $($Data[0].SystemUptime)"


    # --- Identify and Analyze "Sluggish" Intervals ---
    Write-Host "`n[2] Identifying Potential Bottlenecks (based on thresholds):" -ForegroundColor White
    $sluggishIntervals = @()
    foreach ($row in $Data) {
        $issues = @()
        if ([double]$row.CpuPercent -gt $thresholds.CpuPercent) { $issues += "High CPU ($($row.CpuPercent)%)" }
        if ([double]$row.MemoryPercent -gt $thresholds.MemoryPercent) { $issues += "High Memory ($($row.MemoryPercent)%)" }
        if ([double]$row.DiskQueueLength -gt $thresholds.DiskQueueLength) { $issues += "High Disk Queue ($($row.DiskQueueLength))" }
        if ([double]$row.DiskReadLatencyMs -gt $thresholds.DiskReadLatencyMs) { $issues += "High Read Latency ($($row.DiskReadLatencyMs)ms)" }
        if ([double]$row.DiskWriteLatencyMs -gt $thresholds.DiskWriteLatencyMs) { $issues += "High Write Latency ($($row.DiskWriteLatencyMs)ms)" }
        if ($row.GpuUsagePercent -ne 'N/A' -and [double]$row.GpuUsagePercent -gt $thresholds.GpuUsagePercent) { $issues += "High GPU ($($row.GpuUsagePercent)%)" }
        if ($row.TemperatureCelsius -ne 'N/A' -and [double]$row.TemperatureCelsius -gt $thresholds.TemperatureCelsius) { $issues += "High Temperature ($($row.TemperatureCelsius)°C)" }
        if ([double]$row.DpcTimePercent -gt $thresholds.DpcTimePercent) { $issues += "High DPC Time ($($row.DpcTimePercent)%)" }

        if ($issues.Count -gt 0) {
            $sluggishIntervals += [PSCustomObject]@{
                Timestamp = $row.Timestamp
                Issues = $issues -join ", "
                TopCpuProc = $row.TopCpuProc1Name
                TopMemProc = $row.TopMemProc1Name
                TopIoProc = $row.TopIoProc1Name
            }
        }
    }

    if ($sluggishIntervals.Count -gt 0) {
        Write-Host "  Found $($sluggishIntervals.Count) intervals with potential performance issues:" -ForegroundColor Yellow
        $sluggishIntervals | Format-Table -AutoSize | Out-String | Write-Host
    }
    else {
        Write-Host "  No significant performance issues detected based on the defined thresholds." -ForegroundColor Green
    }


    # --- Top Processes Analysis ---
    Write-Host "`n[3] Persistent High-Resource Processes (across all intervals):" -ForegroundColor White
    $allProcs = @{}
    foreach ($row in $Data) {
        for ($i = 1; $i -le $TopProcessesCount; $i++) {
            # Aggregate CPU consumers
            $procName = $row."TopCpuProc${i}Name"
            if ($procName) {
                if (-not $allProcs.ContainsKey($procName)) { $allProcs[$procName] = @{ CpuHits=0; MemHits=0; IoHits=0 } }
                $allProcs[$procName].CpuHits++
            }
            # Aggregate Memory consumers
            $procName = $row."TopMemProc${i}Name"
            if ($procName) {
                if (-not $allProcs.ContainsKey($procName)) { $allProcs[$procName] = @{ CpuHits=0; MemHits=0; IoHits=0 } }
                $allProcs[$procName].MemHits++
            }
            # Aggregate I/O consumers
            $procName = $row."TopIoProc${i}Name"
            if ($procName) {
                if (-not $allProcs.ContainsKey($procName)) { $allProcs[$procName] = @{ CpuHits=0; MemHits=0; IoHits=0 } }
                $allProcs[$procName].IoHits++
            }
        }
    }

    $procStats = $allProcs.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            ProcessName = $_.Name
            TopCpuCount = $_.Value.CpuHits
            TopMemCount = $_.Value.MemHits
            TopIoCount  = $_.Value.IoHits
        }
    }

    Write-Host "  - Top CPU Consumers:"
    $procStats | Sort-Object TopCpuCount -Descending | Select-Object -First 5 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "  - Top Memory Consumers:"
    $procStats | Sort-Object TopMemCount -Descending | Select-Object -First 5 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "  - Top Disk I/O Consumers:"
    $procStats | Sort-Object TopIoCount -Descending | Select-Object -First 5 | Format-Table -AutoSize | Out-String | Write-Host


    # --- Final Conclusions & Recommendations ---
    Write-Host "`n[4] Actionable Insights & Recommendations:" -ForegroundColor Cyan
    if ($maxDiskQueue -gt $thresholds.DiskQueueLength -or $maxReadLatency -gt $thresholds.DiskReadLatencyMs -or $maxWriteLatency -gt $thresholds.DiskWriteLatencyMs) {
        Write-Host "  - RECOMMENDATION: High disk latency or queue length detected." -ForegroundColor Yellow
        Write-Host "    This is a strong indicator of a STORAGE BOTTLENECK. The system is waiting for the disk."
        Write-Host "    Check the 'Top Disk I/O Consumers' list above. Processes like antivirus scanners, indexers (e.g., 'SearchIndexer'), or large file operations are common culprits."
        Write-Host "    Consider checking your disk health (e.g., using CrystalDiskInfo) or upgrading to an SSD if you have an HDD."
    }
    if ($maxTemp -gt $thresholds.TemperatureCelsius) {
        Write-Host "  - RECOMMENDATION: High temperatures detected." -ForegroundColor Yellow
        Write-Host "    Your system may be THERMAL THROTTLING, reducing its performance to prevent overheating."
        Write-Host "    Ensure cooling vents are clear and fans are working. For a laptop, consider a cooling pad."
    }
    if (($Data.DpcTimePercent | Measure-Object -Average).Average -gt 5) {
        Write-Host "  - RECOMMENDATION: Elevated DPC Time detected." -ForegroundColor Yellow
        Write-Host "    This often points to a DRIVER ISSUE (e.g., network, graphics, or storage drivers)."
        Write-Host "    Ensure your main system drivers are up to date from the manufacturer's website (e.g., Dell, HP, Lenovo)."
    }
    if ($sluggishIntervals.Count -eq 0) {
        Write-Host "  - All Clear: System appears to be running smoothly within the monitored period." -ForegroundColor Green
        Write-Host "    If you still experience sluggishness, it might be caused by very short bursts of activity not captured by the $($MonitorIntervalSeconds)s interval."
    }

    Write-Host "`n--- Analysis Complete. Review '$LogFile' for detailed, timestamped data. ---" -ForegroundColor Cyan
}

# --- Main Execution ---
# It is highly recommended to run this script as an Administrator to get all performance counters.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "For best results and to access all metrics (like GPU, Temp, some processes), please run this script as an Administrator."
}

# 1. Start monitoring and collect the data
$collectedData = Start-PerformanceMonitoring -LogFile $LogFile -MonitorIntervalSeconds $MonitorIntervalSeconds -DurationMinutes $DurationMinutes -TopProcessesCount $TopProcessesCount

# 2. After monitoring, immediately analyze the collected data
if ($collectedData) {
    Analyze-PerformanceLog -Data $collectedData -LogFile $LogFile -TopProcessesCount $TopProcessesCount
}
else {
    Write-Error "No data was collected. Analysis cannot proceed."
}
