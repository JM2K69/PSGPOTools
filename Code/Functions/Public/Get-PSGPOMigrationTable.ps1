function Get-PSGPOMigrationTable {
    <#
    .SYNOPSIS
        Reads a migration table (.migtable) of GPMC.
    .DESCRIPTION
        Its entries, checked as GPMC checks them: Type (User, Computer, LocalGroup, GlobalGroup,
        UniversalGroup, UNCPath, Unknown), Source, and how it maps: Mode SameAsSource (the
        reference is kept), ByRelativeName (the same name in the domain of the import), None (the
        account is removed) or Explicit, with its Destination. A UNC path is kept or mapped to
        another path; free text or a SID is not mapped by relative name; a destination is a name.
    .PARAMETER Path
        The migration table.
    .EXAMPLE
        Get-PSGPOMigrationTable -Path C:\backupGPO\prod.migtable | Where-Object Mode -NE SameAsSource
    .OUTPUTS
        PSGPOTools.MigrationEntry
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpomigrationtable/
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.MigrationEntry')]
    param([Parameter(Mandatory)] [string]$Path)

    Read-PSGPOMigrationTable -Path $Path
}
