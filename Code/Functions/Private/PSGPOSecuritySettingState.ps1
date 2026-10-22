<#
    Security settings of a GPO in its GptTmpl.inf (GPOToolsSecurityTemplate), and its advanced
    audit policy in audit.csv (GPOToolsAuditPolicyFile): the value of a setting of the catalog
    (Get-PSGPOSecuritySetting), a new value written in place, and the report of the defined
    settings for the Settings tab, as GPMC shows them.
#>

# Value of a setting in the template (GptTmpl.inf, or audit.csv for the advanced audit
# policy): Defined, Value (typed) and Raw (as written).
function Get-PSGPOSecurityValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateScript({ $_ -is [GPOToolsSecurityTemplate] -or $_ -is [GPOToolsAuditPolicyFile] })] $Template,
        [Parameter(Mandatory)] [GPOToolsSecuritySetting]$Setting
    )

    $raw = $Template.GetValue($Setting.Section, $Setting.Key)
    $defined = $Template.HasValue($Setting.Section, $Setting.Key)
    $value = $null
    $problem = $null
    if ($defined) {
        try { $value = $Setting.ConvertFromRaw("$raw") } catch { $problem = "'$($Setting.Name)': the value '$raw' cannot be read." }
    }
    [pscustomobject]@{ Defined = $defined; Value = $value; Raw = $raw; Problem = $problem }
}

# Writes the value of a setting in the template ($null: not defined). The value is checked
# before anything changes.
function Set-PSGPOSecurityValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateScript({ $_ -is [GPOToolsSecurityTemplate] -or $_ -is [GPOToolsAuditPolicyFile] })] $Template,
        [Parameter(Mandatory)] [GPOToolsSecuritySetting]$Setting,
        [AllowNull()] $Value
    )

    if ($Template -is [GPOToolsAuditPolicyFile]) {
        $Template.SetSubcategory($Setting.Key, $Setting.Name, $(if ($null -ne $Value) { [int]$Setting.ConvertToRaw($Value) }))
        return
    }
    if ($null -eq $Value) {
        $Template.SetValue($Setting.Section, $Setting.Key, $null)
        return
    }
    $raw = $Setting.ConvertToRaw($Value)
    $Template.AddPreamble()
    $Template.SetValue($Setting.Section, $Setting.Key, $raw)
}

# Defined security settings, as the Settings tab of GPMC lists them; the keys the catalog
# does not know (restricted groups, services, file and registry permissions...) as they are.
function Get-PSGPOConfiguredSecuritySetting {
    [CmdletBinding()]
    [OutputType([AvaloniaSettingRow])]
    param(
        [Parameter(Mandatory)] [GPOToolsSecurityTemplate]$Template
    )

    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rows = foreach ($setting in @(Get-PSGPOSecuritySetting | Where-Object Section -NE ([GPOToolsAuditPolicyFile]::Section))) {
        [void]$known.Add("$($setting.Section)|$($setting.Key)")
        $read = Get-PSGPOSecurityValue -Template $Template -Setting $setting
        if (-not $read.Defined) { continue }
        $row = [AvaloniaSettingRow]::new()
        $row.Path = (@('Policies', 'Windows Settings', 'Security Settings') + $setting.Path) -join ' > '
        $row.Name = $setting.Name
        $row.State = if ($read.Problem) { "$($read.Raw) (cannot be read)" } else { $setting.FormatValue($read.Value) }
        $row
    }
    # Sort-Object wraps its output in PSObjects, which Avalonia cannot bind: the rows themselves.
    foreach ($row in @($rows | Sort-Object Path, Name)) { $row.psobject.BaseObject }
    Get-PSGPOConfiguredRestrictedGroup -Template $Template

    foreach ($section in $Template.GetSectionNames()) {
        if ($section -in 'Unicode', 'Version', $script:PSGPORestrictedGroupSection) { continue }
        foreach ($key in $Template.GetKeys($section)) {
            if ($known.Contains("$section|$key")) { continue }
            $row = [AvaloniaSettingRow]::new()
            $row.Path = "Policies > Windows Settings > Security Settings > [$section]"
            $row.Name = $key
            $row.State = "$($Template.GetValue($section, $key))"
            $row.IsExtra = $true
            $row
        }
    }
}

# The advanced audit policy of audit.csv, as the Settings tab of GPMC lists it; a subcategory the
# catalog does not know by its name in the file.
function Get-PSGPOConfiguredAuditSetting {
    [CmdletBinding()]
    [OutputType([AvaloniaSettingRow])]
    param(
        [Parameter(Mandatory)] [GPOToolsAuditPolicyFile]$AuditFile
    )

    $settings = @{}
    foreach ($setting in @(Get-PSGPOSecuritySetting | Where-Object Section -EQ ([GPOToolsAuditPolicyFile]::Section))) { $settings[$setting.Key] = $setting }
    foreach ($line in @($AuditFile.Lines | Where-Object { $_ -isnot [string] })) {
        $setting = $settings[$line.Guid]
        $row = [AvaloniaSettingRow]::new()
        $row.Path = (@('Policies', 'Windows Settings', 'Security Settings') + $(if ($setting) { $setting.Path } else { 'Advanced Audit Policy Configuration', 'Audit Policies' })) -join ' > '
        $row.Name = if ($setting) { $setting.Name } else { $line.Name }
        $row.State = [GPOToolsAuditPolicyFile]::Inclusion[$line.Value]
        $row.IsExtra = -not $setting
        $row
    }
}
