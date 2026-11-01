function Get-PSGPOStarterGpo {
    <#
    .SYNOPSIS
        Gets the Starter GPOs of the domain, as GPMC lists them under Starter GPOs.
    .DESCRIPTION
        A Starter GPO is a set of Administrative Templates a new GPO starts from (New-PSGPO
        -StarterGpo, New GPO > Source Starter GPO in GPMC). GPMC keeps each in a folder of
        SYSVOL\<domain>\StarterGPOs: no object in the directory. The System Starter GPOs are those
        of Microsoft, which GPMC adds with the folder; the Custom ones are those of the domain.
        A folder whose StarterGPO.tmplx cannot be read is returned with its Problem.
    .PARAMETER Name
        Display name of the Starter GPOs, or a pattern with * and ?; all of them when not given.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOStarterGpo
    .EXAMPLE
        Get-PSGPOStarterGpo -Name 'Workstations*' | Select-Object DisplayName, Type, Description
    .OUTPUTS
        PSGPOTools.StarterGpo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpostartergpo/
    .LINK
        New-PSGPOStarterGpo
    .LINK
        New-PSGPO
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.StarterGpo')]
    param(
        [Parameter(Position = 0)] [string]$Name,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    if ($Name) { Find-PSGPOStarterGpoByName -Directory $Directory -Name $Name }
    else { Get-PSGPOStarterGpoData -Directory $Directory }
}
