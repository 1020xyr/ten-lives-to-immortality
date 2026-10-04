$ErrorActionPreference = 'Continue'
$logPath = 'C:\Users\r1523\Desktop\网文\08_电脑安全\排查记录\2026-10-04_银狐木马强制清除日志.txt'
Set-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 开始强制清理" -Encoding UTF8

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
Write-Log "管理员权限：$isAdmin"
if (-not $isAdmin) {
    Write-Log '失败：未获得管理员权限。'
    exit 10
}

$targetPaths = @(
    'C:\ProgramData\kwBSQocb',
    'C:\ProgramData\Tskb8ocU',
    'C:\Program Files (x86)\cyVz5w',
    'C:\Program Files (x86)\0EtQ96',
    'C:\Users\Public\HiTbrb',
    'C:\Windows\Temp\ranchserv.jpg'
)
$allowedTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $targetPaths) {
    [void]$allowedTargets.Add([IO.Path]::GetFullPath($path))
}

foreach ($taskName in @('MicrosoftEdgeUpdateTaskUA Task-S-1-5-18 6U1pQ','Xjkgc')) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    Write-Log "计划任务 $taskName 存在：$([bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue))"
}

Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(oa6LvTpX|Um1wUo|2NN6ng)\.exe$' -or
    $_.ExecutablePath -match 'kwBSQocb|cyVz5w|HiTbrb|Tskb8ocU|0EtQ96'
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Log "终止进程 $($_.Name) PID=$($_.ProcessId)"
}

if (Get-Service -Name TCLService -ErrorAction SilentlyContinue) {
    Stop-Service -Name TCLService -Force -ErrorAction SilentlyContinue
    & sc.exe delete TCLService | ForEach-Object { Write-Log $_ }
}

$deleteFailures = @()
foreach ($target in $targetPaths) {
    $resolved = [IO.Path]::GetFullPath($target)
    if (-not $allowedTargets.Contains($resolved)) {
        $deleteFailures += $resolved
        Write-Log "拒绝未核实路径：$resolved"
        continue
    }
    if (-not (Test-Path -LiteralPath $resolved)) {
        Write-Log "已不存在：$resolved"
        continue
    }

    Write-Log "处理 ACL 和属性：$resolved"
    if (Test-Path -LiteralPath $resolved -PathType Container) {
        & takeown.exe /F $resolved /A /R /D Y | Out-Null
        & icacls.exe $resolved /remove:d '*S-1-5-32-545' /T /C /Q | Out-Null
        & icacls.exe $resolved /inheritance:e /T /C /Q | Out-Null
        & icacls.exe $resolved /grant:r '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null
        & attrib.exe -R -H -S (Join-Path $resolved '*') /S /D
        & attrib.exe -R -H -S $resolved
    } else {
        & takeown.exe /F $resolved /A | Out-Null
        & icacls.exe $resolved /remove:d '*S-1-5-32-545' /C /Q | Out-Null
        & icacls.exe $resolved /grant:r '*S-1-5-32-544:F' /C /Q | Out-Null
        & attrib.exe -R -H -S $resolved
    }

    try {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Log "Remove-Item 失败，改用 .NET 删除：$($_.Exception.Message)"
        try {
            if (Test-Path -LiteralPath $resolved -PathType Container) {
                [IO.Directory]::Delete($resolved, $true)
            } else {
                [IO.File]::Delete($resolved)
            }
        } catch {
            Write-Log ".NET 删除失败：$($_.Exception.Message)"
        }
    }

    $stillExists = Test-Path -LiteralPath $resolved
    Write-Log "删除后仍存在=$stillExists：$resolved"
    if ($stillExists) { $deleteFailures += $resolved }
}

$exclusions = @('C:\', 'C:\Users', 'C:\ProgramData', 'C:\Program Files (x86)')
foreach ($exclusion in $exclusions) {
    Remove-MpPreference -ExclusionPath $exclusion -ErrorAction SilentlyContinue
}
$defenderExclusionKey = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths'
if (Test-Path -LiteralPath $defenderExclusionKey) {
    foreach ($exclusion in $exclusions) {
        Remove-ItemProperty -LiteralPath $defenderExclusionKey -Name $exclusion -ErrorAction SilentlyContinue
    }
}
Write-Log '已处理四个恶意 Defender 排除项。'

$windowsUpdatePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
if (Test-Path -LiteralPath $windowsUpdatePolicy) {
    Remove-ItemProperty -LiteralPath $windowsUpdatePolicy -Name NoAutoUpdate -ErrorAction SilentlyContinue
}
Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\UsoSvc' -Name Start -Type DWord -Value 2 -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\UsoSvc' -Name DelayedAutoStart -Type DWord -Value 1 -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -Type DWord -Value 3 -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Start-Service -Name UsoSvc -ErrorAction SilentlyContinue

$usoStart = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\UsoSvc' -Name Start -ErrorAction SilentlyContinue).Start
$medicStart = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name Start -ErrorAction SilentlyContinue).Start
Write-Log "UsoSvc Start=$usoStart；WaaSMedicSvc Start=$medicStart"

if ($deleteFailures.Count -gt 0) {
    Write-Log "仍无法删除：$($deleteFailures -join '; ')"
    exit 20
}
Write-Log 'FORCED_CLEANUP_COMPLETED'
exit 0

