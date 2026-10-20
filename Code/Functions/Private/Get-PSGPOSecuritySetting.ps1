<#
    Catalog of the security settings (GPOToolsSecuritySetting), read once from the resources of
    the module:
    - Resources/SecuritySettings.json: account policies, Kerberos, audit, user rights, event
      logs and the security options GptTmpl.inf stores in [System Access] (from Microsoft Learn);
    - Resources/SecurityOptions.json: the security options stored as registry values
      ([Registry Values]), generated from the catalog of Windows (CI/Update-SecurityOptionCatalog.ps1).
#>

function Get-PSGPOSecuritySetting {
    [CmdletBinding()]
    [OutputType([GPOToolsSecuritySetting])]
    param(
        # Reads the catalog again instead of returning the one read before.
        [switch]$Force
    )

    if ($script:PSGPOSecuritySettings -and -not $Force) { return $script:PSGPOSecuritySettings }

    $resources = Join-Path $PSScriptRoot 'Resources'
    $settings = [System.Collections.Generic.List[GPOToolsSecuritySetting]]::new()

    function New-Choice {
        param($Choices)
        @(foreach ($choice in @($Choices)) { if ($choice) { [GPOToolsSecurityChoice]@{ Value = "$($choice.Value)"; Text = "$($choice.Text)" } } })
    }

    $main = Get-Content -LiteralPath (Join-Path $resources 'SecuritySettings.json') -Raw | ConvertFrom-Json
    foreach ($entry in $main.Settings) {
        $setting = [GPOToolsSecuritySetting]::new()
        $setting.Name = $entry.Name
        $setting.Path = [string[]]$entry.Path
        $setting.Section = $entry.Section
        $setting.Key = $entry.Key
        $setting.Kind = $entry.Kind
        if ($null -ne $entry.Min) { $setting.Min = [long]$entry.Min }
        if ($null -ne $entry.Max) { $setting.Max = [long]$entry.Max }
        $setting.Unit = $entry.Unit
        $setting.Choices = New-Choice $entry.Choices
        $setting.Reference = $entry.Reference
        $settings.Add($setting)
    }

    # Registry values the editor shows with the password policy, not with the security options.
    $passwordPolicy = @(
        'MACHINE\System\CurrentControlSet\Control\SAM\MinimumPasswordLengthAudit'
        'MACHINE\System\CurrentControlSet\Control\SAM\RelaxMinimumPasswordLengthLimits'
    )
    $options = Get-Content -LiteralPath (Join-Path $resources 'SecurityOptions.json') -Raw | ConvertFrom-Json
    foreach ($entry in $options.SecurityOptions) {
        $setting = [GPOToolsSecuritySetting]::new()
        $setting.Name = $entry.Name
        $setting.Path = if ($entry.Key -in $passwordPolicy) { 'Account Policies', 'Password Policy' } else { 'Local Policies', 'Security Options' }
        $setting.Section = 'Registry Values'
        $setting.Key = $entry.Key
        $setting.Kind = 'RegistryValue'
        $setting.RegistryType = [int]$entry.RegistryType
        $setting.Display = $entry.Display
        $setting.Unit = $entry.Unit
        $setting.Choices = New-Choice $entry.Choices
        # Choices declared without values: shown by their registry type.
        if ($setting.Display -eq 'Choice' -and -not $setting.Choices) {
            $setting.Display = switch ($setting.RegistryType) { 4 { 'Number' } 7 { 'MultiText' } default { 'Text' } }
        }
        $settings.Add($setting)
    }

    foreach ($setting in $settings) { $setting.Id = "$($setting.Section)|$($setting.Key)" }
    $script:PSGPOSecuritySettings = $settings.ToArray()
    $script:PSGPOSecuritySettings
}
