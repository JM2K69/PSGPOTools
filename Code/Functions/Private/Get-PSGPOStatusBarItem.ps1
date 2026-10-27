<#
    Items of the status bar of Show-GPOManagerAvalonia: this computer (name and system), its
    addresses, its domain, and the domain controller the directory was read from. Kept free of
    any Avalonia type so it can be tested without a UI.
#>

function Get-PSGPOStatusBarItem {
    [CmdletBinding()]
    [OutputType([AvaloniaStatusItem])]
    param(
        [Parameter(Mandatory)]
        [GPOToolsPlatform]$Platform,

        [GPOToolsDirectory]$Directory,

        [string]$DirectoryError
    )

    function New-StatusItem {
        param([string]$Icon, [string]$Text, [string]$ToolTip)
        $item = [AvaloniaStatusItem]::new()
        $item.IconData = Get-PSGPOIconData -Name $Icon
        $item.Text = $Text
        $item.ToolTip = if ($ToolTip) { $ToolTip } else { $Text }
        $item
    }

    # This computer: its name, its system, and its role when it is a domain controller.
    $system = if ($Platform.OperatingSystemDescription) { $Platform.OperatingSystemDescription } else { $Platform.OperatingSystem }
    $hostText = "$($Platform.ComputerName) - $system"
    if ($Platform.IsDomainController) { $hostText += Get-PSGPOText ' ({0} domain controller)' $Platform.DomainControllerType }
    New-StatusItem 'desktop' $hostText (Get-PSGPOText 'This computer: {0}' "$Platform")

    $addresses = @($Platform.IPAddresses | Where-Object { $_ })
    if ($addresses.Count) {
        New-StatusItem 'location' "IP $($addresses -join ', ')" (Get-PSGPOText 'Addresses of this computer: {0}' ($addresses -join ', '))
    } else {
        New-StatusItem 'location' (Get-PSGPOText 'No network address') (Get-PSGPOText 'No network interface of this computer is up.')
    }

    $domain = if ($Platform.DomainName) { Get-PSGPOText 'Domain {0}' $Platform.DomainName } else { Get-PSGPOText 'Not in a domain' }
    New-StatusItem 'globe' $domain

    # The domain controller the directory comes from, and the account it was read with.
    if ($Directory -is [GPOToolsLdapDirectory]) {
        # Whether it is the PDC emulator, where GPMC changes the GPOs.
        $role = if (-not $Directory.PdcEmulator) { '' } elseif ($Directory.IsPdcEmulator()) { Get-PSGPOText ', PDC emulator' } else { Get-PSGPOText ', not the PDC emulator ({0})' $Directory.PdcEmulator }
        $roleTip = if ($Directory.PdcEmulator -and -not $Directory.IsPdcEmulator()) { ' ' + (Get-PSGPOText 'GPMC changes the GPOs on the PDC emulator, {0}: Change Domain Controller... in the context menu of the domain.' $Directory.PdcEmulator) } else { '' }
        New-StatusItem 'server' "DC $($Directory.Server) ($($Directory.ServerType)$role)" ((Get-PSGPOText 'Directory {0}' $Directory.Source) + $roleTip)
        if ($Directory.Account) {
            $limited = $Directory.IsLimited()
            $delegated = $Directory.HasDelegation()
            New-StatusItem 'person' (Get-PSGPOText $(if (-not $delegated) { 'Connected as {0} (read only)' } elseif ($limited) { 'Connected as {0} (delegated rights)' } else { 'Connected as {0}' }) $Directory.Account) $(
                if (-not $delegated) { Get-PSGPOText 'The directory is read as {0}, which manages no OU, GPO or WMI filter: nothing can be changed.' $Directory.Account }
                elseif ($limited -and (Test-PSGPOUnmanagedShown)) { Get-PSGPOText 'The directory is read as {0}: it changes only the OUs and GPOs it manages, the others are greyed.' $Directory.Account }
                elseif ($limited) { Get-PSGPOText 'The directory is read as {0}: only the OUs and GPOs it manages are shown.' $Directory.Account }
                else { Get-PSGPOText 'The directory is read as {0}, which manages every OU and GPO.' $Directory.Account })
        }
    } elseif ($Directory.IsDemonstration) {
        New-StatusItem 'server' (Get-PSGPOText 'No domain controller: demonstration directory') (Get-PSGPOText 'No Active Directory or Samba AD domain was discovered: the directory shown is sample data.')
    } elseif ($Directory) {
        New-StatusItem 'server' (Get-PSGPOText 'No domain controller: {0} offline' $Directory.DomainName) (Get-PSGPOText 'Directory {0}' $Directory.Source)
    } elseif ($DirectoryError) {
        New-StatusItem 'server' (Get-PSGPOText 'Domain controller not reached') $DirectoryError
    } else {
        New-StatusItem 'server' (Get-PSGPOText 'No directory read')
    }
}

# The version of HGPM in the status bar of the consoles, with a dot: green when it is the latest
# of the PowerShell Gallery, orange when a newer one is there (its command in the tooltip), grey
# when the Gallery was not read. The Gallery is read as at the import: at most once a day, 8
# seconds at most, never when the check is off (Test-PSGPOUpdateCheckSkipped).
function Get-PSGPOVersionStatusItem {
    [CmdletBinding()]
    [OutputType([AvaloniaStatusItem])]
    param()

    $item = [AvaloniaStatusItem]::new()
    $item.IconData = Get-PSGPOIconData -Name 'info'
    $item.HasBadge = $true
    $installed = Get-PSGPOModuleVersion
    $latest = $null
    try { if (-not (Test-PSGPOUpdateCheckSkipped)) { $latest = Get-PSGPOLatestGalleryVersion -Installed $installed.Version } } catch { $latest = $null }
    if ($latest -and $latest -gt $installed.Version) {
        $item.Text = Get-PSGPOText 'HGPM {0}: {1} available' $installed.Version $latest
        $item.ToolTip = Get-PSGPOText 'HGPM {0} is on the PowerShell Gallery: {1}, then open a new PowerShell session.' $latest (Get-PSGPOUpdateCommand -InstalledPath $installed.Path -Latest $latest)
        $item.BadgeBrush = '#CA5010'
    } elseif ($latest) {
        $item.Text = "HGPM $($installed.Version)"
        $item.ToolTip = Get-PSGPOText 'HGPM {0}: the latest version of the PowerShell Gallery.' $installed.Version
        $item.BadgeBrush = '#107C10'
    } else {
        $item.Text = "HGPM $($installed.Version)"
        $item.ToolTip = Get-PSGPOText 'HGPM {0}: the PowerShell Gallery was not read (no network, or the check is off), the updates are unknown.' $installed.Version
    }
    $item
}
