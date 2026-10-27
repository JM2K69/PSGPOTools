<#
    Report of a GPO, as Get-GPOReport of GPMC: its details, links, security filtering, delegation and
    WMI filter, its client-side extensions, the settings of its computer and user configurations as
    the Settings tab lists them, and what the console does not interpret. An object
    (PSGPOTools.GpoReport); an XML document of HGPM (not the schema of the reports of GPMC), in
    English; or an HTML page in one file, readable without the console, in the language of the
    interface.
#>

$script:PSGPOReportNamespace = 'https://jm2k69.github.io/PSGPOTools/schemas/gpo-report/1'

# The report of a GPO: the files of its folder read once.
function Get-PSGPOReportData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $settings = Get-PSGPOFolderSetting -Files $Directory.ReadGpoFolder($Gpo) -MachineExtensionNames $Gpo.MachineExtensionNames -UserExtensionNames $Gpo.UserExtensionNames
    $permissions = $null
    try {
        $permissions = @(Get-PSGPOPermissionRow -Directory $Directory -Gpo $Gpo | ForEach-Object { [pscustomobject]@{ Trustee = $_.Trustee; Permission = $_.Permission; Inherited = $_.Inherited; Denied = $_.Denied } })
    } catch {
        $problems.Add("The permissions of the GPO are not read: $($_.Exception.GetBaseException().Message)")
    }
    $filter = $Directory.GetWmiFilter($Gpo)
    $rows = { param($Rows) , [object[]]@($Rows | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Name = $_.Name; State = $_.State; Options = $_.Options } }) }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.GpoReport'
        DisplayName = $Gpo.DisplayName
        Id = $Gpo.Id
        Domain = $Directory.DomainName
        DistinguishedName = $Gpo.DistinguishedName
        Owner = $Gpo.Owner
        Status = $Gpo.GetStatus()
        ApprovalState = $Gpo.ApprovalState
        ComputerVersion = $Gpo.GetComputerVersion()
        UserVersion = $Gpo.GetUserVersion()
        Modified = $Gpo.Modified
        WmiFilter = if ($filter) { "$($filter.Name): $($filter.GetQueryText())" } elseif ($null -ne $Gpo.WmiFilterId) { "{$($Gpo.WmiFilterId.ToString().ToUpperInvariant())}: not in the domain anymore" }
        SecurityFiltering = $Gpo.SecurityFiltering
        DeniedTo = $Gpo.DeniedTo
        Links = [object[]]@(foreach ($pair in @($Directory.GetLinksOf($Gpo) | Sort-Object { $_.Som.DistinguishedName.Length }, { $_.Som.DistinguishedName })) {
                [pscustomobject]@{ Name = $pair.Som.Name; Container = $pair.Som.DistinguishedName; Enabled = $pair.Link.Enabled; Enforced = $pair.Link.Enforced; Order = $pair.Link.Order }
            })
        Permissions = $permissions
        Extensions = [object[]]@(Get-PSGPODeclaredExtension -MachineExtensionNames $Gpo.MachineExtensionNames -UserExtensionNames $Gpo.UserExtensionNames |
                ForEach-Object { [pscustomobject]@{ Scope = $_.Scope; Guid = $_.Guid; Name = $_.Name; Interpreted = $_.Storage -in 'Read', 'Registry' } })
        Computer = & $rows $settings.Machine
        User = & $rows $settings.User
        NotInterpreted = & $rows $settings.Uninterpreted
        Problems = [string[]]$problems
        ReadBy = if ($Directory.Account) { $Directory.Account } else { [Environment]::UserName }
        Generated = [datetime]::UtcNow
        Version = "$((Get-PSGPOModuleVersion).Version)"
    }
}

# Reports as an XML document of HGPM (Get-PSGPOReport -ReportType Xml), in English.
function ConvertTo-PSGPOReportXml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [object[]]$Report)

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.MemoryStream]::new()
    $xml = [System.Xml.XmlWriter]::Create($stream, $settings)
    $ns = $script:PSGPOReportNamespace
    $date = { param($Value) if ($Value) { ([datetime]$Value).ToUniversalTime().ToString('o', [cultureinfo]::InvariantCulture) } }
    $bool = { param($Value) if ($Value) { 'true' } else { 'false' } }
    $element = {
        param([string]$Name, [System.Collections.IDictionary]$Attributes, [string]$Text)
        $xml.WriteStartElement($Name, $ns)
        foreach ($key in $Attributes.Keys) { if ($null -ne $Attributes[$key] -and "$($Attributes[$key])" -ne '') { $xml.WriteAttributeString($key, "$($Attributes[$key])") } }
        if ($Text) { $xml.WriteString($Text) }
        $xml.WriteEndElement()
    }
    $settingList = {
        param([string]$Name, [object[]]$Rows)
        $xml.WriteStartElement($Name, $ns)
        foreach ($row in @($Rows)) { & $element 'Setting' ([ordered]@{ path = $row.Path; name = $row.Name; state = $row.State }) $row.Options }
        $xml.WriteEndElement()
    }
    $xml.WriteStartDocument()
    $xml.WriteStartElement('GpoReports', $ns)
    $first = @($Report)[0]
    $xml.WriteAttributeString('generated', (& $date $first.Generated))
    $xml.WriteAttributeString('generatedBy', "HGPM $($first.Version)")
    foreach ($item in $Report) {
        $xml.WriteStartElement('Gpo', $ns)
        $xml.WriteAttributeString('id', "{$($item.Id.ToString().ToUpperInvariant())}")
        $xml.WriteAttributeString('name', $item.DisplayName)
        $xml.WriteAttributeString('domain', $item.Domain)
        & $element 'Details' ([ordered]@{
                distinguishedName = $item.DistinguishedName; owner = $item.Owner; status = $item.Status; approval = $item.ApprovalState
                computerVersion = $item.ComputerVersion; userVersion = $item.UserVersion; modified = (& $date $item.Modified); wmiFilter = $item.WmiFilter
                readBy = $item.ReadBy
            })
        $xml.WriteStartElement('Links', $ns)
        foreach ($link in @($item.Links)) { & $element 'Link' ([ordered]@{ name = $link.Name; container = $link.Container; enabled = (& $bool $link.Enabled); enforced = (& $bool $link.Enforced); order = $link.Order }) }
        $xml.WriteEndElement()
        $xml.WriteStartElement('SecurityFiltering', $ns)
        if ($null -eq $item.SecurityFiltering) { $xml.WriteAttributeString('read', 'false') }
        foreach ($name in @($item.SecurityFiltering)) { & $element 'Trustee' ([ordered]@{}) $name }
        foreach ($name in @($item.DeniedTo)) { & $element 'Trustee' ([ordered]@{ denied = 'true' }) $name }
        $xml.WriteEndElement()
        $xml.WriteStartElement('Permissions', $ns)
        if ($null -eq $item.Permissions) { $xml.WriteAttributeString('read', 'false') }
        foreach ($permission in @($item.Permissions)) { & $element 'Permission' ([ordered]@{ trustee = $permission.Trustee; permission = $permission.Permission; inherited = (& $bool $permission.Inherited); denied = (& $bool $permission.Denied) }) }
        $xml.WriteEndElement()
        $xml.WriteStartElement('Extensions', $ns)
        foreach ($extension in @($item.Extensions)) { & $element 'Extension' ([ordered]@{ scope = $extension.Scope; guid = $extension.Guid; name = $extension.Name; interpreted = (& $bool $extension.Interpreted) }) }
        $xml.WriteEndElement()
        & $settingList 'Computer' $item.Computer
        & $settingList 'User' $item.User
        & $settingList 'NotInterpreted' $item.NotInterpreted
        if (@($item.Problems).Count) {
            $xml.WriteStartElement('Problems', $ns)
            foreach ($problem in $item.Problems) { & $element 'Problem' ([ordered]@{}) $problem }
            $xml.WriteEndElement()
        }
        $xml.WriteEndElement()
    }
    $xml.WriteEndElement()
    $xml.WriteEndDocument()
    $xml.Flush()
    $xml.Dispose()
    [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
}

# Reports as an HTML page in one file (Get-PSGPOReport -ReportType Html): its texts in the language
# of the interface, the settings by their path, what the console does not interpret in its own box.
function ConvertTo-PSGPOReportHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [object[]]$Report)

    # &, <, >, " and ' only: the letters of the language stay as they are (UTF-8).
    $encode = { param($Text) [System.Security.SecurityElement]::Escape("$Text") }
    $show = { param($Text) (& $encode (ConvertTo-PSGPODisplayText "$Text")) -replace '\r?\n', '<br>' }
    $language = if ($script:PSGPOLanguage) { $script:PSGPOLanguage } else { 'en-US' }
    $culture = [cultureinfo]::GetCultureInfo($language)
    $date = { param($Value) if ($Value) { ([datetime]$Value).ToLocalTime().ToString('g', $culture) } else { Get-PSGPOText 'unknown date' } }
    $yesNo = { param($Value) Get-PSGPOText $(if ($Value) { 'Yes' } else { 'No' }) }
    $html = [System.Text.StringBuilder]::new()
    $add = { param([string]$Text) [void]$html.Append($Text).Append("`n") }
    $table = {
        param([string[]]$Header, [object[]]$Rows)
        & $add "<table><thead><tr>$(@($Header | ForEach-Object { "<th>$(& $encode $_)</th>" }) -join '')</tr></thead><tbody>"
        foreach ($cells in $Rows) { & $add "<tr>$(@($cells | ForEach-Object { "<td>$_</td>" }) -join '')</tr>" }
        & $add '</tbody></table>'
    }
    $settingsPart = {
        param([string]$Title, [object[]]$Rows, [string]$Class)
        $attribute = if ($Class) { " class='$Class'" } else { '' }
        & $add "<h2$attribute>$(& $encode $Title)</h2>"
        if (-not @($Rows).Count) { & $add "<p class=`"none`">$(& $encode (Get-PSGPOText 'No settings defined.'))</p>"; return }
        foreach ($group in @($Rows | Group-Object Path)) {
            & $add "<h3>$(& $show $group.Name)</h3>"
            & $table @((Get-PSGPOText 'Setting'), (Get-PSGPOText 'State'), (Get-PSGPOText 'Options')) @(foreach ($row in $group.Group) { , @((& $show $row.Name), (& $show $row.State), (& $show $row.Options)) })
        }
    }

    $title = if (@($Report).Count -eq 1) { @($Report)[0].DisplayName } else { Get-PSGPOText 'Report of {0} GPOs' @($Report).Count }
    & $add "<!DOCTYPE html>`n<html lang=`"$(& $encode $language)`">`n<head>`n<meta charset=`"utf-8`">`n<title>$(& $encode $title)</title>"
    & $add @'
<style>
  :root { color-scheme: light dark; --text: #1b1b1b; --muted: #616161; --line: #d1d1d1; --head: #f3f3f3; --accent: #0f6cbd; --warn: #ca5010; --bg: #ffffff; }
  @media (prefers-color-scheme: dark) { :root { --text: #f0f0f0; --muted: #b5b5b5; --line: #3d3d3d; --head: #262626; --accent: #62abf5; --warn: #f7894a; --bg: #1b1b1b; } }
  body { font-family: 'Segoe UI', system-ui, sans-serif; color: var(--text); background: var(--bg); margin: 24px; line-height: 1.4; }
  h1 { font-size: 22px; margin: 0 0 4px; } h2 { font-size: 17px; margin: 24px 0 8px; color: var(--accent); }
  h3 { font-size: 13px; font-weight: 600; margin: 14px 0 6px; color: var(--muted); }
  .sub, .none { color: var(--muted); } section.gpo { margin-bottom: 48px; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; margin-bottom: 8px; }
  th, td { border: 1px solid var(--line); padding: 5px 8px; text-align: left; vertical-align: top; }
  th { background: var(--head); } td:first-child { width: 34%; }
  .warn { color: var(--warn); } .box { border: 1px solid var(--warn); border-radius: 4px; padding: 4px 12px 8px; margin-top: 16px; }
  @media print { body { margin: 0; } section.gpo { page-break-after: always; } }
</style>
</head>
<body>
'@
    foreach ($item in $Report) {
        & $add '<section class="gpo">'
        & $add "<h1>$(& $encode $item.DisplayName)</h1>"
        & $add "<p class=`"sub`">$(& $encode (Get-PSGPOText 'Domain {0}, read by {1} on {2}, with HGPM {3}' $item.Domain $item.ReadBy (& $date $item.Generated) $item.Version))</p>"

        & $add "<h2>$(& $encode (Get-PSGPOText 'Details'))</h2>"
        $details = @(
            , @((& $encode (Get-PSGPOText 'Unique ID')), (& $encode "{$($item.Id.ToString().ToUpperInvariant())}"))
            , @((& $encode (Get-PSGPOText 'GPO status')), (& $show $item.Status))
            if ($item.ApprovalState) { , @((& $encode (Get-PSGPOText 'Approval')), (& $encode (Get-PSGPOText $(if ($item.ApprovalState -eq 'Pending') { 'Waiting for approval' } else { 'Approved' })))) }
            if ($item.Owner) { , @((& $encode (Get-PSGPOText 'Owner')), (& $encode $item.Owner)) }
            , @((& $encode (Get-PSGPOText 'Computer version')), (& $encode $item.ComputerVersion))
            , @((& $encode (Get-PSGPOText 'User version')), (& $encode $item.UserVersion))
            , @((& $encode (Get-PSGPOText 'Modified')), (& $encode (& $date $item.Modified)))
            , @((& $encode (Get-PSGPOText 'WMI filter')), (& $encode $(if ($item.WmiFilter) { $item.WmiFilter } else { Get-PSGPOText 'None' })))
            , @((& $encode (Get-PSGPOText 'Distinguished name')), (& $encode $item.DistinguishedName))
        )
        & $table @((Get-PSGPOText 'Property'), (Get-PSGPOText 'Value')) $details

        & $add "<h2>$(& $encode (Get-PSGPOText 'Links ({0})' @($item.Links).Count))</h2>"
        if (@($item.Links).Count) {
            & $table @((Get-PSGPOText 'Location'), (Get-PSGPOText 'Enforced'), (Get-PSGPOText 'Link enabled'), (Get-PSGPOText 'Link order')) @(foreach ($link in $item.Links) {
                    , @("$(& $encode $link.Name)<br><span class=`"sub`">$(& $encode $link.Container)</span>", (& $yesNo $link.Enforced), (& $yesNo $link.Enabled), (& $encode $link.Order))
                })
        } else { & $add "<p class=`"none`">$(& $encode (Get-PSGPOText 'Not linked'))</p>" }

        & $add "<h2>$(& $encode (Get-PSGPOText 'Security Filtering'))</h2>"
        $filtering = if ($null -eq $item.SecurityFiltering) { Get-PSGPOText 'Not read (no access to the permissions of the GPO)' }
            elseif (-not @($item.SecurityFiltering).Count) { Get-PSGPOText 'Nobody: the GPO applies to no computer or user' }
            else { @($item.SecurityFiltering) -join ', ' }
        & $add "<p>$(& $encode $filtering)</p>"
        if (@($item.DeniedTo).Count) { & $add "<p>$(& $encode (Get-PSGPOText 'Denied to: {0}' (@($item.DeniedTo) -join ', ')))</p>" }

        & $add "<h2>$(& $encode (Get-PSGPOText 'Delegation'))</h2>"
        if ($null -eq $item.Permissions) { & $add "<p class=`"none`">$(& $encode (Get-PSGPOText 'Not read (no access to the permissions of the GPO)'))</p>" }
        else {
            & $table @((Get-PSGPOText 'Name'), (Get-PSGPOText 'Allowed Permissions'), (Get-PSGPOText 'Inherited')) @(foreach ($permission in $item.Permissions) {
                    , @((& $encode $permission.Trustee), (& $encode (Get-PSGPOText (Get-PSGPOPermissionText -Permission $permission.Permission))), (& $yesNo $permission.Inherited))
                })
        }

        & $add "<h2>$(& $encode (Get-PSGPOText 'Client-side extensions'))</h2>"
        if (@($item.Extensions).Count) {
            & $table @((Get-PSGPOText 'Name'), (Get-PSGPOText 'Configuration'), (Get-PSGPOText 'Interpreted by HGPM')) @(foreach ($extension in $item.Extensions) {
                    , @("$(& $show $extension.Name)<br><span class=`"sub`">$(& $encode $extension.Guid)</span>", (& $encode (Get-PSGPOText $(if ($extension.Scope -eq 'Machine') { 'Computer' } else { 'User' }))),
                        $(if ($extension.Interpreted) { & $yesNo $true } else { "<span class=`"warn`">$(& $yesNo $false)</span>" }))
                })
        } else { & $add "<p class=`"none`">$(& $encode (Get-PSGPOText 'None'))</p>" }

        & $settingsPart (Get-PSGPOText 'Computer Configuration ({0})' (Get-PSGPOText $(if ($item.Status -match 'Computer configuration settings disabled|All settings disabled') { 'Disabled' } else { 'Enabled' }))) $item.Computer
        & $settingsPart (Get-PSGPOText 'User Configuration ({0})' (Get-PSGPOText $(if ($item.Status -match 'User configuration settings disabled|All settings disabled') { 'Disabled' } else { 'Enabled' }))) $item.User
        if (@($item.NotInterpreted).Count) {
            & $add '<div class="box">'
            & $settingsPart (Get-PSGPOText 'Settings the console does not interpret ({0})' @($item.NotInterpreted).Count) $item.NotInterpreted 'warn'
            & $add "<p class=`"sub`">$(& $encode (Get-PSGPOText 'The computers apply them, but the console does not show what they do: review them with GPMC, or in the files of the GPO, before approving it.'))</p>"
            & $add '</div>'
        }
        foreach ($problem in @($item.Problems)) { & $add "<p class=`"warn`">$(& $encode $problem)</p>" }
        & $add '</section>'
    }
    & $add '</body>'
    & $add '</html>'
    $html.ToString()
}
