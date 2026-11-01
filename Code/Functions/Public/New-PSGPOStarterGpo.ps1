function New-PSGPOStarterGpo {
    <#
    .SYNOPSIS
        Creates a Custom Starter GPO in the domain, empty or with the Administrative Templates of a GPO.
    .DESCRIPTION
        As GPMC "New Starter GPO": a folder of SYSVOL\<domain>\StarterGPOs with its
        StarterGPO.tmplx (its name and description), created with the StarterGPOs folder when the
        domain has none. -FromGpo gives it the Administrative Templates of a GPO (Machine and User
        Registry.pol, and their comments): a Starter GPO holds no other settings, its security
        settings, preferences or scripts are not taken. New GPOs then start from it (New-PSGPO
        -StarterGpo, or New GPO in GPMC).
    .PARAMETER Name
        Display name of the new Starter GPO.
    .PARAMETER Description
        Its description, as the Comment of GPMC (several lines allowed).
    .PARAMETER FromGpo
        Display name of a GPO whose Administrative Templates the Starter GPO takes.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        New-PSGPOStarterGpo -Name 'Workstations - Baseline' -Description 'What every workstation GPO starts from' -FromGpo 'C - Workstations - Security Baseline Windows 11'
    .OUTPUTS
        PSGPOTools.StarterGpo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/new-psgpostartergpo/
    .LINK
        Get-PSGPOStarterGpo
    .LINK
        Remove-PSGPOStarterGpo
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.StarterGpo')]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Description = '',
        [string]$FromGpo,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    Use-PSGPODomainConfiguration -Directory $Directory
    $Name = $Name.Trim()
    if (-not $Name) { throw 'The name of the Starter GPO is required.' }
    $existing = @(Get-PSGPOStarterGpoData -Directory $Directory | Where-Object { [string]::Equals($_.DisplayName, $Name, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($existing.Count) { throw "A Starter GPO named '$Name' already exists in $($Directory.DomainName)." }
    $settings = @{}
    if ($FromGpo) {
        $sources = @(Find-PSGPOByName -Directory $Directory -Name $FromGpo -ErrorAction Stop)
        if ($sources.Count -ne 1) { throw "-FromGpo gives one GPO: '$FromGpo' gives $($sources.Count) ($(@($sources.DisplayName) -join ', '))." }
        $settings = Select-PSGPOStarterSettingFile -Files $Directory.ReadGpoFolder($sources[0])
        if (-not $settings.Count) { Write-Warning "The GPO '$($sources[0].DisplayName)' has no Administrative Template: the Starter GPO '$Name' is empty." }
    }
    $what = if ($FromGpo) { "Create it with the Administrative Templates of the GPO '$FromGpo'" } else { 'Create it' }
    if (-not $PSCmdlet.ShouldProcess("Starter GPO '$Name' in $($Directory.DomainName)", $what)) { return }

    $id = [guid]::NewGuid()
    $Directory.WriteStarterGpo($id, $Name, (New-PSGPOStarterGpoFile -Id $id -DisplayName $Name -Description $Description -Settings $settings))
    @(Get-PSGPOStarterGpoData -Directory $Directory | Where-Object Id -EQ $id)[0]
}
