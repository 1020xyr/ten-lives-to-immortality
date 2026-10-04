$ErrorActionPreference = 'Continue'

$reportDirectory = 'C:\Users\r1523\Desktop\网文\08_电脑安全\排查记录'
$logPath = Join-Path $reportDirectory '2026-10-04_银狐木马清除日志.txt'
New-Item -ItemType Directory -LiteralPath $reportDirectory -Force | Out-Null
Start-Transcript -LiteralPath $logPath -Force

try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        throw '清理脚本未以管理员权限运行。'
    }

    $targetTasks = @(
        'MicrosoftEdgeUpdateTaskUA Task-S-1-5-18 6U1pQ',
        'Xjkgc'
    )

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

    Write-Host '停止并删除恶意计划任务...'
    foreach ($taskName in $targetTasks) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host "已删除计划任务：$taskName"
        } else {
            Write-Host "计划任务已不存在：$taskName"
        }
    }

    Write-Host '终止已知恶意进程...'
    $maliciousProcesses = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^(oa6LvTpX|Um1wUo|2NN6ng)\.exe$' -or
        $_.ExecutablePath -match 'kwBSQocb|cyVz5w|HiTbrb|Tskb8ocU|0EtQ96'
    }
    foreach ($process in $maliciousProcesses) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "已终止：$($process.Name) PID=$($process.ProcessId)"
    }

    Write-Host '删除恶意驱动服务残留...'
    $service = Get-CimInstance Win32_Service -Filter "Name='TCLService'" -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name 'TCLService' -Force -ErrorAction SilentlyContinue
        & sc.exe delete 'TCLService'
    }

    Write-Host '删除已核实的恶意文件和目录...'
    foreach ($target in $targetPaths) {
        $resolved = [IO.Path]::GetFullPath($target)
        if (-not $allowedTargets.Contains($resolved)) {
            throw "拒绝删除未经核实的路径：$resolved"
        }
        if (-not (Test-Path -LiteralPath $resolved)) {
            Write-Host "目标已不存在：$resolved"
            continue
        }

        Get-ChildItem -LiteralPath $resolved -Force -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }
        (Get-Item -LiteralPath $resolved -Force).Attributes = 'Normal'

        try {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        } catch {
            if (Test-Path -LiteralPath $resolved -PathType Container) {
                & takeown.exe /F $resolved /A /R /D Y | Out-Null
                & icacls.exe $resolved /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null
            } else {
                & takeown.exe /F $resolved /A | Out-Null
                & icacls.exe $resolved /grant '*S-1-5-32-544:F' /C /Q | Out-Null
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        }
        Write-Host "已删除：$resolved"
    }

    Write-Host '移除恶意 Defender 排除项...'
    $exclusions = @('C:\', 'C:\Users', 'C:\ProgramData', 'C:\Program Files (x86)')
    foreach ($exclusion in $exclusions) {
        try {
            Remove-MpPreference -ExclusionPath $exclusion -ErrorAction Stop
            Write-Host "已请求移除 Defender 排除项：$exclusion"
        } catch {
            Write-Warning "无法通过 Defender cmdlet 移除 $exclusion：$($_.Exception.Message)"
        }
    }

    Write-Host '恢复 Windows Update 设置...'
    $windowsUpdatePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    if (Test-Path -LiteralPath $windowsUpdatePolicy) {
        Remove-ItemProperty -LiteralPath $windowsUpdatePolicy -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue
    }
    & sc.exe config UsoSvc start= auto
    & sc.exe config WaaSMedicSvc start= demand
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Start-Service -Name UsoSvc -ErrorAction SilentlyContinue

    Write-Host '执行清理后核验...'
    foreach ($target in $targetPaths) {
        [pscustomobject]@{ Type = 'Path'; Name = $target; Exists = Test-Path -LiteralPath $target }
    }
    foreach ($taskName in $targetTasks) {
        [pscustomobject]@{ Type = 'Task'; Name = $taskName; Exists = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) }
    }
    Get-CimInstance Win32_Service | Where-Object Name -in 'wuauserv','UsoSvc','WaaSMedicSvc','WinDefend','MDCoreSvc' |
        Select-Object Name,State,StartMode

    Write-Host 'CLEANUP_COMPLETED'
} finally {
    Stop-Transcript
}

