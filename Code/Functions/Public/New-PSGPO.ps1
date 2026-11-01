function New-PSGPO {
    <#
    .SYNOPSIS
        Creates a GPO in the domain, empty or from a template.
    .DESCRIPTION
        Like GPMC "New GPO": the GPO is created in the domain (on Windows with New-GPO of RSAT, on
        Linux with samba-tool and Kerberos), not linked. With -Template, it starts with the
        settings of a backup (Get-PSGPOBackup -Template: the backups with the template label of
        the configuration, Backup.TemplateLabel), whatever GPO or domain it comes from: its files,
        checked against their SHA-256, and their client-side extensions. With -StarterGpo, it starts
        with the Administrative Templates of a Starter GPO of the domain (Get-PSGPOStarterGpo), as
        New GPO > Source Starter GPO in GPMC. -Comment gives it a comment (GPO.cmt, the Comment of
        the Details tab of GPMC).
    .PARAMETER Name
        Display name of the new GPO.
    .PARAMETER Template
        Backup whose settings the GPO starts with.
    .PARAMETER StarterGpo
        Display name of the Starter GPO whose Administrative Templates the GPO starts with.
    .PARAMETER Status
        GPO status: Enabled (default), ComputerOnly (user settings disabled) or UserOnly
        (computer settings disabled).
    .PARAMETER Comment
        Comment of the GPO (several lines allowed).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        New-PSGPO -Name 'C - Kiosks - Baseline' -Status ComputerOnly -Comment 'CHG-2041: kiosks of the halls'
    .EXAMPLE
        $Template = Get-PSGPOBackup -Path /srv/gpo-backups -Template -Name 'Template - Servers' | Select-Object -First 1
        New-PSGPO -Name 'C - Servers - Lyon' -Template $Template
    .EXAMPLE
        New-PSGPO -Name 'C - Workstations - Lyon' -StarterGpo 'Workstations - Baseline'
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/new-psgpo/
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

        [string]$StarterGpo,

        [ValidateSet('Enabled', 'ComputerOnly', 'UserOnly')]
        [string]$Status = 'Enabled',

        [string]$Comment,

        [GPOToolsDirectory]$Directory,

        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    if ($Template -and $StarterGpo) { throw 'Give -Template or -StarterGpo: a GPO starts from one of them.' }
    # Its files checked, or the Starter GPO found and read, before anything is created.
    if ($Template) { $null = Get-PSGPOVerifiedBackupFile -Backup $Template }
    $starter = $null
    if ($StarterGpo) {
        $starters = @(Find-PSGPOStarterGpoByName -Directory $Directory -Name $StarterGpo)
        if ($starters.Count -ne 1) { throw "-StarterGpo gives one Starter GPO: '$StarterGpo' gives $($starters.Count) ($(@($starters.DisplayName) -join ', '))." }
        $starter = $starters[0]
        if ($starter.Problem) { throw $starter.Problem }
    }
    $what = if ($Template) { "Create it from the template '$($Template.DisplayName)'" } elseif ($starter) { "Create it from the Starter GPO '$($starter.DisplayName)'" } else { 'Create it' }
    if (-not $PSCmdlet.ShouldProcess("GPO '$Name' in $($Directory.DomainName)", $what)) { return }

    $gpo = $Directory.NewGpo($Name)
    try {
        if ($Template) { Copy-PSGPOBackupSetting -Directory $Directory -Gpo $gpo -Backup $Template }
        if ($starter) { Copy-PSGPOStarterSetting -Directory $Directory -Gpo $gpo -StarterGpo $starter }
        $flags = @{ Enabled = 0; ComputerOnly = 1; UserOnly = 2 }[$Status]
        if ($flags -ne $gpo.Flags) { $Directory.SetGpoStatus($gpo, $flags) }
        if ($Comment) { $Directory.WriteGpoComment($gpo, $Comment) }
    } catch {
        Write-Error "The GPO '$Name' is created, but not completed: $($_.Exception.GetBaseException().Message)"
    }
    $gpo
}
