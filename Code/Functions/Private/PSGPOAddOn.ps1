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
        [scriptblock]$ReportHtml
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
