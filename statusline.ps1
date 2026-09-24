# Reads the JSON Claude Code pipes on stdin and prints a one-line status.
$stdinRaw = [Console]::In.ReadToEnd()
$data = $stdinRaw | ConvertFrom-Json

$Esc = [char]27
function Color-ByPct($text, $pct) {
    if ($null -eq $pct) { return $text }
    $code = if ($pct -ge 80) { "196" } elseif ($pct -ge 50) { "220" } else { "42" }
    return "${Esc}[38;5;${code}m${text}${Esc}[0m"
}

$model = $data.model.display_name
if (-not $model) { $model = $data.model.id }

$effort = $data.effort.level
if ($effort) { $model = "$model ($effort)" }

$cost = $data.cost.total_cost_usd
$costStr = if ($null -ne $cost) { "`${0:N2}" -f $cost } else { "`$0.00" }

$usedPct = $data.context_window.used_percentage
$ctxStr = if ($null -ne $usedPct) { Color-ByPct ("{0}% ctx" -f [math]::Round($usedPct)) $usedPct } else { "-- ctx" }

$clockStr = (Get-Date).ToString("HH:mm")

$durMs = $data.cost.total_duration_ms
$durStr = if ($null -ne $durMs) {
    $ts = [TimeSpan]::FromMilliseconds($durMs)
    if ($ts.TotalHours -ge 1) { "{0:00}:{1:00}:{2:00}" -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds }
    else { "{0:00}:{1:00}" -f $ts.Minutes, $ts.Seconds }
} else { "00:00" }

$added = $data.cost.total_lines_added
$removed = $data.cost.total_lines_removed
$linesStr = if ($added -or $removed) { "+$added/-$removed" } else { $null }

$cwd = $data.cwd
$dirName = if ($cwd) { Split-Path $cwd -Leaf } else { "" }

$branch = ""
if ($cwd -and (Test-Path (Join-Path $cwd ".git"))) {
    try {
        $b = git -C "$cwd" rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $b) { $branch = " ($b)" }
    } catch {}
}

function Format-ResetTime($epochSeconds) {
    if ($null -eq $epochSeconds) { return $null }
    return ([DateTimeOffset]::FromUnixTimeSeconds($epochSeconds).ToLocalTime().ToString("HH:mm"))
}

function Format-ResetDayTime($epochSeconds) {
    if ($null -eq $epochSeconds) { return $null }
    return ([DateTimeOffset]::FromUnixTimeSeconds($epochSeconds).ToLocalTime().ToString("ddd HH:mm"))
}

$fiveHour = $data.rate_limits.five_hour.used_percentage
$fiveHourReset = Format-ResetTime $data.rate_limits.five_hour.resets_at
$fiveHourStr = if ($null -ne $fiveHour) {
    $raw = if ($fiveHourReset) { "5h:{0}%(->{1})" -f [math]::Round($fiveHour), $fiveHourReset }
           else { "5h:{0}%" -f [math]::Round($fiveHour) }
    Color-ByPct $raw $fiveHour
} else { $null }

$sevenDay = $data.rate_limits.seven_day.used_percentage
$sevenDayReset = Format-ResetDayTime $data.rate_limits.seven_day.resets_at
$sevenDayStr = if ($null -ne $sevenDay) {
    $raw = if ($sevenDayReset) { "wk:{0}%(->{1})" -f [math]::Round($sevenDay), $sevenDayReset }
           else { "wk:{0}%" -f [math]::Round($sevenDay) }
    Color-ByPct $raw $sevenDay
} else { $null }

$dimSep = "${Esc}[2m|${Esc}[0m"

$parts = @("[$model]", $costStr, $ctxStr, $clockStr, $durStr)
if ($linesStr) { $parts += $linesStr }
if ($fiveHourStr -or $sevenDayStr) {
    $planParts = @($fiveHourStr, $sevenDayStr) | Where-Object { $_ }
    $parts += ($planParts -join " $dimSep ")
}
if ($dirName) { $parts += "$dirName$branch" }

[Console]::Write(($parts -join " $dimSep "))

function Find-LatestHook($pluginDir, $hookRelPath) {
    if (-not (Test-Path $pluginDir)) { return $null }
    $latest = Get-ChildItem $pluginDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    $hookPath = Join-Path $latest.FullName $hookRelPath
    if (Test-Path $hookPath) { return $hookPath }
    return $null
}

# Append the ponytail mode badge if active (doesn't read stdin, safe to chain).
$ponytailScript = Find-LatestHook "$env:USERPROFILE\.claude\plugins\cache\ponytail\ponytail" "hooks\ponytail-statusline.ps1"
$badgeWritten = $false
if ($ponytailScript) {
    [Console]::Write(" $dimSep ")
    & $ponytailScript
    $badgeWritten = $true
}

# Append the caveman mode badge. It reads session_id from stdin, which the
# parent already consumed above — rewind stdin so the child sees the same JSON.
$cavemanScript = Find-LatestHook "$env:USERPROFILE\.claude\plugins\cache\caveman\caveman" "src\hooks\caveman-statusline.ps1"
if ($cavemanScript) {
    [Console]::Write("  ")
    if ($badgeWritten) { [Console]::Write("$dimSep ") }
    [Console]::SetIn([System.IO.StringReader]::new($stdinRaw))
    & $cavemanScript
}
