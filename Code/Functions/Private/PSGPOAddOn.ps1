<#
    Add-ons of HGPM: modules installed beside it that add to it. They are called add-ons, not
    extensions: a GPO has client-side extensions.

    An add-on is a module named HGPM.<name> whose manifest tags it HGPMAddOn
    (PrivateData.PSData.Tags). It requires the version of HGPM it was tested with
    (RequiredModules) and, when it is imported, registers itself with Register-PSGPOAddOn, giving
    the contract of the add-on points it was built for ($script:PSGPOAddOnContract) and its hooks.
    The core loads the add-ons installed the first time something needs them (a window, a report,
    the status bar), in every process: each console of Start-HGPM runs in its own. An add-on that
    cannot be loaded, or that was built for another contract, is left out and said in the
    technical log: the consoles open without it, and the management of the GPOs never depends on
    it. PSGPOTOOLS_NO_ADDON=1 loads none (the tests).

    The hooks of the contract 1, each a scriptblock, each called in a try: an error leaves what
    HGPM does as it is.
      WindowLogo  param($Kind): the path of the image of the windows, Icon (their icon, square,
                  256 x 256) or Header (their header, shown in 44 x 44); nothing: that of HGPM.
      ReportHtml  param($Html): the HTML report changed, returned; its markers <!-- hgpm:head -->,
                  <!-- hgpm:body-start --> and <!-- hgpm:body-end --> say where to add.
      ReportFormat  formats of file the reports are saved in besides HTML and XML, each a
                  hashtable: Name (PDF), Extension (pdf), TypeName (the type of file of the save
                  dialog: a text, or a text per language @{ 'en-US' = ...; 'fr-FR' = ... }) and
                  Save, param($Html, $Path): the HTML report (ReportHtml applied) written to $Path
                  in that format. Its error is the one of the save: the file was asked for.
      BeforeChange  param($Directory): called before each change of the directory (GPOs, links,
                  WMI filters, permissions, settings, configuration: its AssertWritable). Its
                  error refuses the change, with its message: nothing is written.
      AuditEntry  param($Entry): the line of the audit log before it is written (a dictionary);
                  what the add-on knows of the change goes in $Entry.Details.
      ConsoleField  fields of the toolbar of the GPO console, each a hashtable: Name, Label and
                  ToolTip (a text, or a text per language), Placeholder, Width, Get (its value)
                  and Set, param($Value): the value typed, kept by the add-on; its error is said.
    Their settings for the domain are in AddOns.<name> of the configuration of the domain
    (Get-PSGPOAddOnConfiguration, Save-PSGPOAddOnConfiguration).
    A hook added to the contract keeps it: an add-on built before the hook works as it did, and
    one that uses it requires the version of HGPM that has it.
#>

# The contract of the add-on points of this version of the core: what Register-PSGPOAddOn takes
# and what the core asks of an add-on. An add-on built for another contract is not loaded.
$script:PSGPOAddOnContract = 1

# The add-ons of this process: those installed (Found, looked for once), those registered or left
# out (Items), and the images of the windows they give (Logo, asked once per kind).
$script:PSGPOAddOn = @{ Searched = $false; Found = @(); Loaded = $false; Items = [System.Collections.Generic.List[object]]::new(); Logo = @{} }

# The add-ons installed, not loaded: the newest version of each module HGPM.* tagged HGPMAddOn.
function Find-PSGPOAddOn {
    [CmdletBinding()]
    param()

    if ($env:PSGPOTOOLS_NO_ADDON -eq '1') { return }
    if (-not $script:PSGPOAddOn.Searched) {
        $script:PSGPOAddOn.Found = @(Get-Module -ListAvailable -Name 'HGPM.*' -ErrorAction SilentlyContinue |
                Where-Object { @($_.Tags) -contains 'HGPMAddOn' } | Group-Object -Property Name |
                ForEach-Object { $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1 })
        $script:PSGPOAddOn.Searched = $true
    }
    $script:PSGPOAddOn.Found
}

# An add-on registered, or left out with the reason why.
function Add-PSGPOAddOnItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [version]$Version,
        [string]$Edition,
        [int]$Contract,
        [Parameter(Mandatory)] [ValidateSet('Loaded', 'Refused', 'Failed')] [string]$State,
        [string]$Reason,
        [string]$Path,
        [scriptblock]$WindowLogo,
        [scriptblock]$ReportHtml,
        [object[]]$ReportFormat = @(),
        [scriptblock]$BeforeChange,
        [scriptblock]$AuditEntry,
        [object[]]$ConsoleField = @()
    )

    $known = @($script:PSGPOAddOn.Items | Where-Object Name -EQ $Name)
    foreach ($item in $known) { [void]$script:PSGPOAddOn.Items.Remove($item) }
    $script:PSGPOAddOn.Items.Add([pscustomobject]@{
            PSTypeName = 'PSGPOTools.AddOn'
            Name = $Name
            Edition = $(if ($Edition) { $Edition } else { $Name })
            Version = $Version
            Contract = $Contract
            State = $State
            Reason = $Reason
            Path = $Path
            WindowLogo = $WindowLogo
            ReportHtml = $ReportHtml
            ReportFormat = @($ReportFormat)
            BeforeChange = $BeforeChange
            AuditEntry = $AuditEntry
            ConsoleField = @($ConsoleField)
        })
    # The images asked before are asked again with this add-on.
    $script:PSGPOAddOn.Logo = @{}
}

# Loads the add-ons installed, once in a process. Never throws: an add-on left out is said in the
# technical log.
function Initialize-PSGPOAddOn {
    [CmdletBinding()]
    param()

    if ($script:PSGPOAddOn.Loaded) { return }
    $script:PSGPOAddOn.Loaded = $true
    foreach ($module in @(Find-PSGPOAddOn)) {
        # Imported already: it registered itself.
        if (@($script:PSGPOAddOn.Items | Where-Object Name -EQ $module.Name).Count) { continue }
        try {
            # Global: its commands are those of the session, as if the user had imported it.
            Import-Module -Name $module.Path -Global -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false
            if (-not @($script:PSGPOAddOn.Items | Where-Object Name -EQ $module.Name).Count) {
                Add-PSGPOAddOnItem -Name $module.Name -Version $module.Version -State Failed -Path $module.ModuleBase -Reason 'It did not register itself (Register-PSGPOAddOn).'
            }
        } catch {
            # A contract refused by Register-PSGPOAddOn keeps its reason.
            $refused = @($script:PSGPOAddOn.Items | Where-Object { $_.Name -eq $module.Name -and $_.State -eq 'Refused' })
            if (-not $refused.Count) {
                Add-PSGPOAddOnItem -Name $module.Name -Version $module.Version -State Failed -Path $module.ModuleBase -Reason $_.Exception.GetBaseException().Message
            }
        }
        $item = @($script:PSGPOAddOn.Items | Where-Object Name -EQ $module.Name)[0]
        if ($item.State -ne 'Loaded') {
            Write-PSGPOLogEntry -Level Warning -Source 'Add-ons' -Message "The add-on $($module.Name) $($module.Version) is not loaded: $($item.Reason) The consoles open without it." -Detail ([ordered]@{ Path = $module.ModuleBase })
        }
    }
}

# The add-ons of this process: loaded, refused or failed, with the reason why (the About of the launcher).
function Get-PSGPOAddOnState {
    [CmdletBinding()]
    param()

    Initialize-PSGPOAddOn
    @($script:PSGPOAddOn.Items)
}

# The add-ons loaded, for their hooks and their version.
function Get-PSGPOLoadedAddOn {
    [CmdletBinding()]
    param()

    @(Get-PSGPOAddOnState | Where-Object State -EQ 'Loaded')
}

# The version of HGPM with those of the add-ons loaded, as the consoles and the reports show it:
# 0.3.0, or 0.3.0 + Contoso 0.3.0.1.
function Get-PSGPOEditionVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $text = "$((Get-PSGPOModuleVersion).Version)"
    foreach ($addOn in @(Get-PSGPOLoadedAddOn)) { $text += " + $($addOn.Edition) $($addOn.Version)" }
    $text
}

# The image of the windows an add-on gives (its hook WindowLogo), asked once per kind: the path of
# a file, or $null for the one of HGPM (no add-on, no file, an error said in the technical log).
function Get-PSGPOAddOnWindowLogo {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [ValidateSet('Icon', 'Header')] [string]$Kind)

    Initialize-PSGPOAddOn
    if ($script:PSGPOAddOn.Logo.ContainsKey($Kind)) { return $script:PSGPOAddOn.Logo[$Kind] }
    $path = $null
    foreach ($addOn in @(Get-PSGPOLoadedAddOn | Where-Object WindowLogo)) {
        try {
            $given = "$(& $addOn.WindowLogo $Kind)"
            if ($given -and (Test-Path -LiteralPath $given -PathType Leaf)) { $path = (Get-Item -LiteralPath $given).FullName; break }
            if ($given) { Write-PSGPOLogEntry -Level Warning -Source 'Add-ons' -Message "The image $Kind of $($addOn.Edition) is not a file: $given. The one of HGPM is kept." }
        } catch {
            Write-PSGPOLogEntry -Level Warning -Source 'Add-ons' -Message "The image $Kind of $($addOn.Edition) cannot be read: $($_.Exception.GetBaseException().Message) The one of HGPM is kept." -ErrorRecord $_
        }
    }
    $script:PSGPOAddOn.Logo[$Kind] = $path
    $path
}

# A format of report an add-on gives (its hook ReportFormat), checked: Name, Extension (letters and
# digits, not those of HGPM: html, htm, xml), TypeName (a text, or a text per language) and Save
# (a scriptblock). Throws what is wrong: the add-on does not register.
function ConvertTo-PSGPOAddOnReportFormat {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] [object]$Format)

    if ($Format -isnot [System.Collections.IDictionary]) { throw 'ReportFormat: each format is a hashtable: Name, Extension, TypeName and Save.' }
    $name = "$($Format['Name'])".Trim()
    $extension = "$($Format['Extension'])".Trim().TrimStart('.').ToLowerInvariant()
    $typeName = $Format['TypeName']
    $save = $Format['Save']
    if (-not $name) { throw 'ReportFormat: a format has no Name.' }
    if ($extension -notmatch '^[a-z0-9]{1,10}$') { throw "ReportFormat $($name): its Extension '$($Format['Extension'])' is not letters and digits (pdf)." }
    if ($extension -in 'html', 'htm', 'xml') { throw "ReportFormat $($name): .$extension is a format of HGPM." }
    $texts = if ($typeName -is [System.Collections.IDictionary]) {
        $byLanguage = [ordered]@{}
        foreach ($key in $typeName.Keys) { if ("$($typeName[$key])".Trim()) { $byLanguage["$key"] = "$($typeName[$key])".Trim() } }
        $byLanguage
    } elseif ("$typeName".Trim()) { [ordered]@{ 'en-US' = "$typeName".Trim() } }
    if (-not $texts -or -not $texts.Count) { throw "ReportFormat $($name): it has no TypeName (the type of file of the save dialog)." }
    if ($save -isnot [scriptblock]) { throw "ReportFormat $($name): its Save is not a scriptblock param(`$Html, `$Path)." }
    [pscustomobject]@{ Name = $name; Extension = $extension; TypeName = $texts; Save = $save }
}

# The formats of report of the add-ons loaded, each extension once (the first add-on that gives
# it): Name, Extension, TypeName in the language of the interface (else English, else the first
# given), Save, and the Edition that gives it.
function Get-PSGPOAddOnReportFormat {
    [CmdletBinding()]
    param()

    $language = if ($script:PSGPOLanguage) { $script:PSGPOLanguage } else { 'en-US' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($addOn in @(Get-PSGPOLoadedAddOn)) {
        foreach ($format in @($addOn.ReportFormat)) {
            if (-not $format -or -not $seen.Add($format.Extension)) { continue }
            $typeName = if ($format.TypeName.Contains($language)) { $format.TypeName[$language] }
                elseif ($format.TypeName.Contains('en-US')) { $format.TypeName['en-US'] }
                else { @($format.TypeName.Values)[0] }
            [pscustomobject]@{ Name = $format.Name; Extension = $format.Extension; TypeName = $typeName; Save = $format.Save; Edition = $addOn.Edition }
        }
    }
}

# Writes an HTML report to a file: in the format an add-on gives for the extension of $Path (its
# Save), else as the HTML page itself (UTF-8). The error of an add-on is the one of the save: the
# file was asked for. The file written.
function Write-PSGPOReportHtmlFile {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)] [string]$Html,
        [Parameter(Mandatory)] [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).TrimStart('.')
    $format = if ($extension) { @(Get-PSGPOAddOnReportFormat | Where-Object Extension -EQ $extension)[0] }
    if (-not $format) {
        [System.IO.File]::WriteAllText($Path, $Html, [System.Text.UTF8Encoding]::new($false))
        return Get-Item -LiteralPath $Path
    }
    # The file of before is not taken for the one the add-on made.
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Remove-Item -LiteralPath $Path -Force }
    try {
        $null = & $format.Save $Html $Path
    } catch {
        Write-PSGPOLogEntry -Level Error -Source 'Add-ons' -Message "$($format.Edition) did not write the report as $($format.Name): $($_.Exception.GetBaseException().Message)" -ErrorRecord $_ -Detail ([ordered]@{ Path = $Path })
        throw
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$($format.Edition) wrote no file $Path ($($format.Name))." }
    Get-Item -LiteralPath $Path
}

# The HTML report as the add-ons change it (their hook ReportHtml), each in turn; an add-on that
# fails, or returns nothing, leaves it as it was.
function Invoke-PSGPOAddOnReportHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Html)

    foreach ($addOn in @(Get-PSGPOLoadedAddOn | Where-Object ReportHtml)) {
        try {
            $changed = "$(& $addOn.ReportHtml $Html)"
            if ($changed) { $Html = $changed }
        } catch {
            Write-PSGPOLogEntry -Level Warning -Source 'Add-ons' -Message "The report is not changed by $($addOn.Edition): $($_.Exception.GetBaseException().Message)" -ErrorRecord $_
        }
    }
    $Html
}

# A text an add-on gives: one text, or a text per language (@{ 'en-US' = ...; 'fr-FR' = ... }), as
# an ordered table by language; $null when it gives none.
function ConvertTo-PSGPOAddOnText {
    [CmdletBinding()]
    param([AllowNull()] [object]$Text)

    $texts = [ordered]@{}
    if ($Text -is [System.Collections.IDictionary]) { foreach ($key in $Text.Keys) { if ("$($Text[$key])".Trim()) { $texts["$key"] = "$($Text[$key])".Trim() } } }
    elseif ("$Text".Trim()) { $texts['en-US'] = "$Text".Trim() }
    if ($texts.Count) { $texts }
}

# The text of an add-on in the language of the interface, else English, else the first one given.
function Get-PSGPOAddOnText {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [System.Collections.IDictionary]$Text)

    if (-not $Text -or -not $Text.Count) { return '' }
    $language = if ($script:PSGPOLanguage) { $script:PSGPOLanguage } else { 'en-US' }
    if ($Text.Contains($language)) { return $Text[$language] }
    if ($Text.Contains('en-US')) { return $Text['en-US'] }
    @($Text.Values)[0]
}

# A field of the toolbar an add-on gives (its hook ConsoleField), checked: Name, Label, Get and Set;
# ToolTip, Placeholder and Width (80 to 400 pixels, 160 by default) optional. Throws what is wrong.
function ConvertTo-PSGPOAddOnConsoleField {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowNull()] [object]$Field)

    if ($Field -isnot [System.Collections.IDictionary]) { throw 'ConsoleField: each field is a hashtable: Name, Label, Get and Set.' }
    $name = "$($Field['Name'])".Trim()
    if ($name -notmatch '^\w+$') { throw "ConsoleField: its Name '$name' is not letters and digits." }
    $label = ConvertTo-PSGPOAddOnText -Text $Field['Label']
    if (-not $label) { throw "ConsoleField ${name}: it has no Label." }
    foreach ($key in 'Get', 'Set') { if ($Field[$key] -isnot [scriptblock]) { throw "ConsoleField ${name}: its $key is not a scriptblock." } }
    $width = 160
    if ($null -ne $Field['Width']) {
        if ("$($Field['Width'])" -notmatch '^\d+$' -or [int]$Field['Width'] -lt 80 -or [int]$Field['Width'] -gt 400) { throw "ConsoleField ${name}: its Width '$($Field['Width'])' is not 80 to 400 pixels." }
        $width = [int]$Field['Width']
    }
    [pscustomobject]@{
        Name = $name
        Label = $label
        ToolTip = ConvertTo-PSGPOAddOnText -Text $Field['ToolTip']
        Placeholder = ConvertTo-PSGPOAddOnText -Text $Field['Placeholder']
        Width = $width
        Get = $Field['Get']
        Set = $Field['Set']
    }
}

# The fields of the toolbar of the add-ons loaded, their texts in the language of the interface.
function Get-PSGPOAddOnConsoleField {
    [CmdletBinding()]
    param()

    foreach ($addOn in @(Get-PSGPOLoadedAddOn)) {
        foreach ($field in @($addOn.ConsoleField)) {
            if (-not $field) { continue }
            [pscustomobject]@{
                Name = $field.Name; Edition = $addOn.Edition
                Label = Get-PSGPOAddOnText -Text $field.Label; ToolTip = Get-PSGPOAddOnText -Text $field.ToolTip
                Placeholder = Get-PSGPOAddOnText -Text $field.Placeholder; Width = $field.Width
                Get = $field.Get; Set = $field.Set
            }
        }
    }
}

# Before a change of the directory (GPOToolsDirectory.AssertWritable): each add-on may refuse it
# (its hook BeforeChange throws), with its message; the change is not made.
function Invoke-PSGPOAddOnBeforeChange {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Directory)

    foreach ($addOn in @(Get-PSGPOLoadedAddOn | Where-Object BeforeChange)) {
        try {
            $null = & $addOn.BeforeChange $Directory
        } catch {
            $message = $_.Exception.GetBaseException().Message
            Write-PSGPOLogEntry -Level Warning -Source 'Add-ons' -Message "A change of $($Directory.DomainName) is refused by $($addOn.Edition): $message"
            throw $message
        }
    }
}

# The line of the audit log as the add-ons complete it (their hook AuditEntry), each in turn; an
# add-on that fails leaves it as it was.
function Invoke-PSGPOAddOnAuditEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Collections.IDictionary]$Entry)

    foreach ($addOn in @(Get-PSGPOLoadedAddOn | Where-Object AuditEntry)) {
        try {
            $null = & $addOn.AuditEntry $Entry
        } catch {
            Write-PSGPOLogEntry -Level Warning -Source 'Add-ons' -Message "The line of the audit log is not completed by $($addOn.Edition): $($_.Exception.GetBaseException().Message)" -ErrorRecord $_
        }
    }
}

# The settings of an add-on in the configuration of the domain in use (AddOns.<Name>): a table,
# empty when the domain has none.
function Get-PSGPOAddOnConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [ValidatePattern('^\w+$')] [string]$Name)

    $addOns = (Get-PSGPOConfigurationData).AddOns
    if ($addOns -is [hashtable] -and $addOns[$Name] -is [hashtable]) { return $addOns[$Name] }
    @{}
}

# Writes the settings of an add-on in the configuration of the domain of $Directory (AddOns.<Name>),
# the other settings as the domain has them: an administrator of the domain; $null or an empty table
# removes them. Written in the audit log as every configuration saved.
function Save-PSGPOAddOnConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [ValidatePattern('^\w+$')] [string]$Name,
        [AllowNull()] [hashtable]$Settings
    )

    # As the domain has it now: another console may have changed it.
    Use-PSGPODomainConfiguration -Directory $Directory -Force
    $state = $script:PSGPOConfigurationState
    if ($state.Problem) { throw "The configuration of the domain $($state.Path) cannot be read, nothing is written: $($state.Problem)" }
    $known = @{}
    foreach ($key in $state.Override.Keys) { if ($key -ne 'AddOns') { $known[$key] = $state.Override[$key] } }
    $addOns = @{}
    if ($state.Override.AddOns -is [hashtable]) { foreach ($key in $state.Override.AddOns.Keys) { $addOns[$key] = $state.Override.AddOns[$key] } }
    if ($Settings -and $Settings.Count) { $addOns[$Name] = $Settings } else { $addOns.Remove($Name) }
    # The caller asked: its own confirmation, not that of the configuration.
    Save-PSGPODomainConfiguration -Directory $Directory -Values (ConvertTo-PSGPOFlatConfiguration -Data $known) -AddOns $addOns -Confirm:$false
}
