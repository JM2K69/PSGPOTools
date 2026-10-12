<#
.SYNOPSIS
    Generates PSGPOTools/Resources/SecurityOptions.json, the catalog of the Security Options
    stored as registry values in GptTmpl.inf ([Registry Values]).
.DESCRIPTION
    Reads the catalog the Group Policy editor builds its Security Options from: the registry key
    HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SeCEdit\Reg Values (one subkey per
    registry value, '/' for '\'), or %windir%\inf\sceregvl.inf with -FromInf. Each option gives
    its registry path and type, how the value is shown (boolean, number with its unit, text,
    choices, multi-line text, bitmask) and its choices.

    The display names are resource references (@wsecedit.dll,-59001): they are resolved with
    SHLoadIndirectString, in the language of Windows. Run it on an English Windows, the names
    of the module being in English.

    Windows only, run by hand when a new version of Windows adds options.
.PARAMETER FromInf
    Reads sceregvl.inf instead of the registry.
.PARAMETER OutputPath
    JSON file to write.
#>
[CmdletBinding()]
param(
    [switch]$FromInf,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..' 'PSGPOTools' 'Resources' 'SecurityOptions.json')
)

if (-not $IsWindows) { throw 'Windows only: the catalog and its display names come from Windows.' }
Add-Type -Namespace PSGPOToolsBuild -Name Shell -MemberDefinition @'
[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
public static extern int SHLoadIndirectString(string source, System.Text.StringBuilder output, int size, System.IntPtr reserved);
'@

$displays = @{ '0' = 'Boolean'; '1' = 'Number'; '2' = 'Text'; '3' = 'Choice'; '4' = 'MultiText'; '5' = 'Bitmask' }

# Names Windows does not resolve (resource missing in wsecedit.dll, option without string):
# the titles of their pages on Microsoft Learn.
$knownNames = @{
    'MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash' = 'Network security: Do not store LAN Manager hash value on next password change'
    'MACHINE\System\CurrentControlSet\Services\LDAP\LDAPClientConfidentiality' = 'Network security: LDAP client encryption requirements'
}

$infStrings = @{}
function Resolve-String {
    param([string]$Reference)
    $value = $Reference
    if ($value -match '^%(.+)%$' -and $infStrings.ContainsKey($Matches[1])) { $value = $infStrings[$Matches[1]] }
    if ($value.StartsWith('@')) {
        $text = [System.Text.StringBuilder]::new(2048)
        if ([PSGPOToolsBuild.Shell]::SHLoadIndirectString($value, $text, $text.Capacity, [IntPtr]::Zero) -eq 0) { return $text.ToString() }
    }
    $value
}

# "value|name" items of choices and bitmasks.
function ConvertTo-Choice {
    param([string[]]$Items)
    @(foreach ($item in $Items) {
            if (-not $item) { continue }
            $value, $text = $item -split '\|', 2
            [ordered]@{ Value = $value; Text = Resolve-String $text }
        })
}

function New-Option {
    param([string]$Key, [string]$Name, [string]$ValueType, [string]$DisplayType, [string]$Unit, [string[]]$Choices)
    $option = [ordered]@{
        Key = $Key
        Name = Resolve-String $Name
        RegistryType = [int]$ValueType
        Display = $displays[$DisplayType]
    }
    if ($option.Name -match '^(@|%)' -and $knownNames.ContainsKey($Key)) { $option.Name = $knownNames[$Key] }
    if ($option.Name -match '^(@|%)' -or -not $option.Name) { Write-Warning "No display name for ${Key}: $($option.Name)"; return }
    if ($Unit) { $option.Unit = Resolve-String $Unit }
    if ($Choices) { $option.Choices = ConvertTo-Choice $Choices }
    $option
}

$options = if (-not $FromInf) {
    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SeCEdit\Reg Values'
    foreach ($item in Get-ChildItem -LiteralPath $root) {
        $choices = @($item.GetValue('DisplayChoices')) + @($item.GetValue('DisplayFlags')) | Where-Object { $_ }
        New-Option -Key ($item.PSChildName -replace '/', '\') -Name $item.GetValue('DisplayName') -ValueType $item.GetValue('ValueType') `
            -DisplayType $item.GetValue('DisplayType') -Unit $item.GetValue('DisplayUnit') -Choices $choices
    }
} else {
    $section = ''
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath (Join-Path $env:windir 'inf' 'sceregvl.inf') -Encoding Unicode) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith(';')) { continue }
        if ($trimmed -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
        if ($section -eq 'Register Registry Values') { $entries.Add($trimmed) }
        elseif ($section -eq 'Strings' -and $trimmed -match '^([^=]+?)\s*=\s*"?(.*?)"?$') { $infStrings[$Matches[1]] = $Matches[2] }
    }
    foreach ($entry in $entries) {
        $fields = $entry -split ','
        # Legacy entries list only the path: no type, no name.
        if ($fields.Count -lt 4) { continue }
        $rest = @($fields | Select-Object -Skip 4)
        $unit = if ($fields[3] -eq '1' -and $rest.Count) { $rest[0] }
        $choices = if ($fields[3] -in '3', '5') { $rest }
        New-Option -Key $fields[0] -Name $fields[2] -ValueType $fields[1] -DisplayType $fields[3] -Unit $unit -Choices $choices
    }
}

$source = if ($FromInf) { '%windir%\inf\sceregvl.inf' } else { 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SeCEdit\Reg Values' }
$catalog = [ordered]@{
    Source = "Generated by CI/Update-SecurityOptionCatalog.ps1 from $source (Windows $([Environment]::OSVersion.Version))"
    SecurityOptions = @($options | Sort-Object { $_.Name })
}
$catalog | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "$(@($options).Count) security options written to $OutputPath"
