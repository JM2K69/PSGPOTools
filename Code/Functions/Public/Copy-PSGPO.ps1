function Copy-PSGPO {
    <#
    .SYNOPSIS
        Copies a GPO into a new GPO of its domain, as Copy and Paste of GPMC: its settings, status, client-side extensions, WMI filter and comment; not its links.
    .DESCRIPTION
        The new GPO gets the files of the folder of the GPO in SYSVOL (its settings and its
        comment), its status, the client-side extensions it declares and its WMI filter. Its links
        are not copied: link the copy where it applies (New-PSGPOLink). Its permissions are those of
        a new GPO, as GPMC gives by default; -CopyAcl gives it those of the GPO instead (Preserve the
        existing permissions, in GPMC), but the ones a level of permission cannot give (denied,
        custom), which are said. With the approval workflow, the copy of a creator waits for its
        approval as any new GPO, and the approval gives its security filtering: -CopyAcl is refused
        to a creator.
    .PARAMETER Name
        Display name of the GPO to copy (one GPO).
    .PARAMETER TargetName
        Display name of the new GPO.
    .PARAMETER CopyAcl
        The permissions of the GPO copied, not those of a new GPO.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Copy-PSGPO -Name 'C - Workstations - BitLocker' -TargetName 'C - Laptops - BitLocker'
    .EXAMPLE
        Copy-PSGPO -Name 'C - Servers - Baseline' -TargetName 'C - Servers - Baseline (test)' -CopyAcl
    .OUTPUTS
        GPOToolsGpo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/copy-psgpo/
    .LINK
        New-PSGPOLink
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([GPOToolsGpo])]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$TargetName,
        [switch]$CopyAcl,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    $sources = @(Find-PSGPOByName -Directory $Directory -Name $Name -ErrorAction Stop)
    if ($sources.Count -ne 1) { throw "-Name gives one GPO to copy: '$Name' gives $($sources.Count) ($(@($sources.DisplayName) -join ', '))." }
    $source = $sources[0]
    if ($CopyAcl -and $Directory.IsWorkflowCreator()) {
        throw 'With the approval workflow, the approval gives a GPO its security filtering: copy it without -CopyAcl, it waits for its approval as any new GPO.'
    }
    $what = "Copy it to a new GPO '$("$TargetName".Trim())'$(if ($CopyAcl) { ', with its permissions' })"
    if (-not $PSCmdlet.ShouldProcess("GPO '$($source.DisplayName)' in $($Directory.DomainName)", $what)) { return }

    $new = $Directory.NewGpo($TargetName)
    try {
        foreach ($row in @(Copy-PSGPOContent -Directory $Directory -Source $source -Target $new -CopyAcl:$CopyAcl)) {
            Write-Warning "Permission not copied to '$($new.DisplayName)': $($row.Name) ($(Get-PSGPOPermissionText -Permission $row.Permission)$(if ($row.Denied) { ', denied' })); give it in the Delegation tab if it is needed."
        }
    } catch {
        Write-Error "The GPO '$($new.DisplayName)' is created, but not completed: $($_.Exception.GetBaseException().Message)"
    }
    $new
}
