<#
    Scripts of a GPO ([MS-GPSCR]), as the Group Policy editor shows them under Policies > Windows
    Settings: Scripts (Startup/Shutdown) of the computer, Scripts (Logon/Logoff) of the user. Their
    lists are in scripts.ini and psscripts.ini (GPOToolsScriptsFile), their files in the folder of
    their kind in the GPO (Machine\Scripts\Startup). The client-side extension of the scripts runs
    them, with the tool of the scope declared.

    A startup script runs as SYSTEM on every computer the GPO applies to: the Settings tab lists each
    one with its file in the GPO, its size and SHA-256, so that a change of its content shows when
    two versions are compared, and the files no script runs.
#>

$script:PSGPOScriptKind = @{ Machine = @('Startup', 'Shutdown'); User = @('Logon', 'Logoff') }
$script:PSGPOScriptNodeName = @{ Machine = 'Scripts (Startup/Shutdown)'; User = 'Scripts (Logon/Logoff)' }
# The key of [ScriptsConfig] that says whether the PowerShell scripts of a kind run first.
$script:PSGPOScriptOrderKey = @{ Startup = 'StartExecutePSFirst'; Logon = 'StartExecutePSFirst'; Shutdown = 'EndExecutePSFirst'; Logoff = 'EndExecutePSFirst' }

# Path of scripts.ini, or psscripts.ini, of a scope in the folder of a GPO.
function Get-PSGPOScriptFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope,
        [switch]$PowerShell
    )

    "$Scope\Scripts\$(if ($PowerShell) { 'psscripts.ini' } else { 'scripts.ini' })"
}

# The file of the GPO a script runs: a command line without a root (a drive, \\, /, %) is a file of
# the folder of its kind; $null for a script outside the GPO.
function Get-PSGPOScriptGpoPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope,
        [Parameter(Mandatory)] [string]$Kind,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$CmdLine
    )

    $line = $CmdLine.Trim().Trim('"')
    if (-not $line -or $line -match '^(\\|/|%|[A-Za-z]:)' -or $line -match '(^|[\\/])\.\.([\\/]|$)') { return $null }
    "$Scope\Scripts\$Kind\$($line -replace '/', '\')"
}

# The scripts of a scope in the files of a GPO, in the order they run in each kind: Kind, Type
# (Script, PowerShell), Order (from 1, in its type), CmdLine, Parameters and Path (its file in the
# GPO, $null for a script outside it).
function Get-PSGPOScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    $lists = @{
        Script = [GPOToolsScriptsFile]::Parse([byte[]]$Files[(Get-PSGPOScriptFilePath -Scope $Scope)])
        PowerShell = [GPOToolsScriptsFile]::Parse([byte[]]$Files[(Get-PSGPOScriptFilePath -Scope $Scope -PowerShell)])
    }
    foreach ($kind in $script:PSGPOScriptKind[$Scope]) {
        foreach ($type in 'Script', 'PowerShell') {
            $order = 0
            foreach ($item in $lists[$type].GetScripts($kind)) {
                $order++
                [pscustomobject]@{
                    Kind = $kind; Type = $type; Order = $order; CmdLine = $item.CmdLine; Parameters = $item.Parameters
                    Path = Get-PSGPOScriptGpoPath -Scope $Scope -Kind $kind -CmdLine $item.CmdLine
                }
            }
        }
    }
}

# Whether the PowerShell scripts of a kind run before the others (First), after them (Last), or as
# the computer decides ($null: not set).
function Get-PSGPOScriptOrder {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsScriptsFile]$PowerShellFile,
        [Parameter(Mandatory)] [string]$Kind
    )

    $value = $PowerShellFile.GetConfig($script:PSGPOScriptOrderKey[$Kind])
    if ($value -ieq 'true') { 'First' } elseif ($value -ieq 'false') { 'Last' }
}

# Sets whether the PowerShell scripts of a kind run first (First), last (Last) or as the computer
# decides ($null).
function Set-PSGPOScriptOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsScriptsFile]$PowerShellFile,
        [Parameter(Mandatory)] [string]$Kind,
        [AllowEmptyString()] [AllowNull()] [ValidateSet('First', 'Last', '')] [string]$Order
    )

    $PowerShellFile.SetConfig($script:PSGPOScriptOrderKey[$Kind], $(if ($Order -eq 'First') { 'true' } elseif ($Order -eq 'Last') { 'false' }))
}

# The text of the file of a script, to read it before it runs: UTF-16 or UTF-8 by its byte order
# mark, else UTF-8; $null for a program or another binary file. The first 256 KB only.
function ConvertFrom-PSGPOScriptContent {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [byte[]]$Bytes)

    $limit = 256KB
    $length = [Math]::Min($Bytes.Length, $limit)
    $text = if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $length - 2) }
        elseif ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $length - 3) }
        else { [System.Text.Encoding]::UTF8.GetString($Bytes, 0, $length) }
    # A NUL, or the MZ of a program: not text.
    if ($text.Contains([char]0) -or ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x4D -and $Bytes[1] -eq 0x5A)) { return $null }
    if ($Bytes.Length -gt $limit) { $text += [Environment]::NewLine + "[... $($Bytes.Length - $limit) more bytes]" }
    $text
}

# The scripts of a scope as the Settings tab lists them (AvaloniaSettingRow): a row per script, with
# its order, its parameters and its file in the GPO (size, SHA-256); the order of the PowerShell
# scripts of a kind when it is set; the files of the folders of the scripts that no script runs.
# The key of a script is its kind, type and command line.
function Get-PSGPOConfiguredScript {
    [CmdletBinding()]
    [OutputType([AvaloniaSettingRow])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.IDictionary]$Files,
        [Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope
    )

    $node = "Policies > Windows Settings > $($script:PSGPOScriptNodeName[$Scope])"
    $run = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seen = @{}
    foreach ($item in @(Get-PSGPOScript -Files $Files -Scope $Scope)) {
        $row = [AvaloniaSettingRow]::new()
        $row.Path = "$node > $($item.Kind)"
        $row.Name = $item.CmdLine
        $row.State = if ($item.Type -eq 'PowerShell') { 'PowerShell script' } else { 'Script' }
        $options = @("Order: $($item.Order)")
        if ($item.Parameters) { $options += "Parameters: $($item.Parameters)" }
        if (-not $item.Path) {
            $options += 'Outside the GPO: the computers run it from there'
        } elseif ($Files.Contains($item.Path)) {
            [void]$run.Add($item.Path)
            $bytes = [byte[]]$Files[$item.Path]
            # A line each, translated in the Settings tab: its file, its size, its hash.
            $options += "In the GPO: $($item.Path)", "$($bytes.Length) bytes", "SHA-256 $((Get-PSGPOFileHash -Bytes $bytes).Substring(0, 12))"
        } else {
            $options += "Not in the GPO: $($item.Path)"
            $row.IsExtra = $true
        }
        $row.Options = $options -join [Environment]::NewLine
        $id = "$($item.Kind)|$($item.Type)|$($item.CmdLine.ToLowerInvariant())"
        $seen[$id] = 1 + $seen[$id]
        $row.Key = "$($row.Path)|$id|$($seen[$id])"
        $row
    }
    $powerShell = [GPOToolsScriptsFile]::Parse([byte[]]$Files[(Get-PSGPOScriptFilePath -Scope $Scope -PowerShell)])
    foreach ($kind in $script:PSGPOScriptKind[$Scope]) {
        $order = Get-PSGPOScriptOrder -PowerShellFile $powerShell -Kind $kind
        if (-not $order) { continue }
        $row = [AvaloniaSettingRow]::new()
        $row.Path = "$node > $kind"
        $row.Name = 'Windows PowerShell scripts'
        $row.State = if ($order -eq 'First') { 'Run first' } else { 'Run last' }
        $row.Key = "$($row.Path)|PowerShellOrder"
        $row
    }
    $lists = @((Get-PSGPOScriptFilePath -Scope $Scope), (Get-PSGPOScriptFilePath -Scope $Scope -PowerShell))
    foreach ($name in @($Files.Keys)) {
        if (-not $name.StartsWith("$Scope\Scripts\", [System.StringComparison]::OrdinalIgnoreCase) -or $name -in $lists -or $run.Contains($name)) { continue }
        $bytes = [byte[]]$Files[$name]
        $row = [AvaloniaSettingRow]::new()
        $row.Path = $node
        $row.Name = $name
        $row.State = 'Not run'
        $row.Options = @('No script of the GPO runs this file.', "$($bytes.Length) bytes", "SHA-256 $((Get-PSGPOFileHash -Bytes $bytes).Substring(0, 12))") -join [Environment]::NewLine
        $row.IsExtra = $true
        $row.Key = "$node|File|$name"
        $row
    }
}
