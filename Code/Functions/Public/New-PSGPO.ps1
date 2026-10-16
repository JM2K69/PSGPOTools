function New-PSGPO {
    <#
    .SYNOPSIS
        Creates a GPO in the domain, empty or from a template.
    .DESCRIPTION
        Like GPMC "New GPO": the GPO is created in the domain (on Windows with New-GPO of RSAT, on
        Linux with samba-tool and Kerberos), not linked. With -Template, it starts with the
        settings of a backup (Get-PSGPOBackup -Template: the backups with the template label of
        the configuration, Backup.TemplateLabel), whatever GPO or domain it comes from: its files,
        checked against their SHA-256, and their client-side extensions.
    .PARAMETER Name
        Display name of the new GPO.
    .PARAMETER Template
        Backup whose settings the GPO starts with.
    .PARAMETER Status
        GPO status: Enabled (default), ComputerOnly (user settings disabled) or UserOnly
        (computer settings disabled).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        New-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly
    .EXAMPLE
        $Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
        New-PSGPO -Name 'C - Servers - Lyon' -Template $Template
    .LINK
        Remove-PSGPO
    .LINK
        Get-PSGPOBackup
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([GPOToolsGpo])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [PSTypeName('PSGPOTools.Backup')]
        $Template,

        [ValidateSet('Enabled', 'ComputerOnly', 'UserOnly')]
        [string]$Status = 'Enabled',

        [GPOToolsDirectory]$Directory,

        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    # Its files checked before anything is created.
    if ($Template) { $null = Get-PSGPOVerifiedBackupFile -Backup $Template }
    $what = if ($Template) { "Create it from the template '$($Template.DisplayName)'" } else { 'Create it' }
    if (-not $PSCmdlet.ShouldProcess("GPO '$Name' in $($Directory.DomainName)", $what)) { return }

    $gpo = $Directory.NewGpo($Name)
    try {
        if ($Template) { Copy-PSGPOBackupSetting -Directory $Directory -Gpo $gpo -Backup $Template }
        $flags = @{ Enabled = 0; ComputerOnly = 1; UserOnly = 2 }[$Status]
        if ($flags -ne $gpo.Flags) { $Directory.SetGpoStatus($gpo, $flags) }
    } catch {
        Write-Error "The GPO '$Name' is created, but not completed: $($_.Exception.GetBaseException().Message)"
    }
    $gpo
}
