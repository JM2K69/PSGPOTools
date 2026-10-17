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
        New-StatusItem 'server' "DC $($Directory.Server) ($($Directory.ServerType))" (Get-PSGPOText 'Directory {0}' $Directory.Source)
        if ($Directory.Account) {
            $limited = $Directory.IsLimited()
            New-StatusItem 'person' (Get-PSGPOText $(if ($limited) { 'Connected as {0} (delegated rights)' } else { 'Connected as {0}' }) $Directory.Account) $(
                if ($limited) { Get-PSGPOText 'The directory is read as {0}: only the OUs and GPOs it manages are shown.' $Directory.Account }
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
