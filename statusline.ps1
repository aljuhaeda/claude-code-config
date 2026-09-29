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

# Short mode badges (P:U ponytail, C:U caveman) up front so they survive truncation.
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
function Mode-Badge($label, $flag, $color) {
    if (-not (Test-Path -LiteralPath $flag)) { return $null }
    $m = ([string](Get-Content -LiteralPath $flag -TotalCount 1)).Trim().ToLower()
    if ($m -eq "off") { return $null }
    $l = if ($m -match '^[a-z]') { $m.Substring(0,1).ToUpper() } else { "F" }
    return "${Esc}[38;5;${color}m${label}:${l}${Esc}[0m"
}
$cavFlag = Join-Path $claudeDir ".caveman-active"
$sid = [string]$data.session_id
if ($sid -match '^[A-Za-z0-9_-]{1,128}$') {
    $sf = Join-Path $claudeDir ".caveman-sessions\$sid.mode"
    if (Test-Path -LiteralPath $sf) { $cavFlag = $sf }
}
$badges = @((Mode-Badge "P" (Join-Path $claudeDir ".ponytail-active") 173), (Mode-Badge "C" $cavFlag 172)) | Where-Object { $_ }

$parts = @("[$model]")
if ($badges) { $parts += ($badges -join " ") }
$parts += @($costStr, $ctxStr, $clockStr, $durStr)
if ($linesStr) { $parts += $linesStr }
if ($fiveHourStr -or $sevenDayStr) {
    $planParts = @($fiveHourStr, $sevenDayStr) | Where-Object { $_ }
    $parts += ($planParts -join " $dimSep ")
}
if ($dirName) { $parts += "$dirName$branch" }

[Console]::Write(($parts -join " $dimSep "))
