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
    if ($Platform.IsDomainController) { $hostText += " ($($Platform.DomainControllerType) domain controller)" }
    New-StatusItem 'desktop' $hostText "This computer: $Platform"

    $addresses = @($Platform.IPAddresses | Where-Object { $_ })
    if ($addresses.Count) {
        New-StatusItem 'location' "IP $($addresses -join ', ')" "Addresses of this computer: $($addresses -join ', ')"
    } else {
        New-StatusItem 'location' 'No network address' 'No network interface of this computer is up.'
    }

    $domain = if ($Platform.DomainName) { "Domain $($Platform.DomainName)" } else { 'Not in a domain' }
    New-StatusItem 'globe' $domain

    # The domain controller the directory comes from, and the account it was read with.
    if ($Directory -is [GPOToolsLdapDirectory]) {
        New-StatusItem 'server' "DC $($Directory.Server) ($($Directory.ServerType))" "Directory $($Directory.Source)"
        if ($Directory.Account) {
            $limited = $Directory.IsLimited()
            New-StatusItem 'person' "Connected as $($Directory.Account)$(if ($limited) { ' (delegated rights)' })" $(
                if ($limited) { "The directory is read as $($Directory.Account): only the OUs and GPOs it manages are shown." }
                else { "The directory is read as $($Directory.Account), which manages every OU and GPO." })
        }
    } elseif ($Directory.IsDemonstration) {
        New-StatusItem 'server' 'No domain controller: demonstration directory' 'No Active Directory or Samba AD domain was discovered: the directory shown is sample data.'
    } elseif ($Directory) {
        New-StatusItem 'server' "No domain controller: $($Directory.DomainName) offline" "Directory $($Directory.Source)"
    } elseif ($DirectoryError) {
        New-StatusItem 'server' 'Domain controller not reached' $DirectoryError
    } else {
        New-StatusItem 'server' 'No directory read'
    }
}
