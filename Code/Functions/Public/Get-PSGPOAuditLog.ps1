function Get-PSGPOAuditLog {
    <#
    .SYNOPSIS
        What the consoles and the commands changed in the domain: the audit log.
    .DESCRIPTION
        Each change the domain accepted, from the console or a command, is a line of the audit
        log: when, by which account, from which computer, on which domain controller, what and on
        what (a GPO, a container, the configuration). The log is in Audit.Path of the configuration
        of the domain (a share the administrators write, the same for every console); by default
        in the folder Audit of the backups of the account. Newest first.
    .PARAMETER Path
        Folder of the audit log; Audit.Path of the configuration by default.
    .PARAMETER Domain
        Domain whose changes are listed; all of them by default.
    .PARAMETER Name
        Display name of a GPO (* and ? make a pattern): only its changes.
    .PARAMETER Action
        Only these actions (NewGpo, NewLink, SetLink, RemoveLink, SetBlockInheritance,
        SetGpoStatus, RemoveGpo, ApproveGpo, PendingGpo, SaveGpoFile, RestoreGpo,
        NewFilteringGroups, SaveConfiguration); * and ? make a pattern.
    .PARAMETER Account
        Only the changes of this account (* and ? make a pattern).
    .PARAMETER After
        Only the changes after this date.
    .PARAMETER Before
        Only the changes before this date.
    .EXAMPLE
        Get-PSGPOAuditLog -Path \\files\gpo-audit -After (Get-Date).AddDays(-7) | Format-Table Time, Account, Action, Target
    .EXAMPLE
        Get-PSGPOAuditLog -Name 'C - Servers - Baseline' -Action SaveGpoFile
    .OUTPUTS
        PSGPOTools.AuditEntry
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpoauditlog/
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.AuditEntry')]
    param(
        [string]$Path,
        [string]$Domain,
        [string]$Name,
        [string[]]$Action,
        [string]$Account,
        [datetime]$After,
        [datetime]$Before
    )

    if (-not $Path) { $Path = Get-PSGPOAuditPath }
    foreach ($entry in @(Read-PSGPOAuditEntry -Path $Path -Domain $Domain)) {
        if ($Name -and -not (Test-PSGPONameMatch -Name $entry.GpoName -Pattern $Name)) { continue }
        if ($Action -and -not @($Action | Where-Object { Test-PSGPONameMatch -Name $entry.Action -Pattern $_ }).Count) { continue }
        if ($Account -and -not (Test-PSGPONameMatch -Name $entry.Account -Pattern $Account)) { continue }
        if ($PSBoundParameters.ContainsKey('After') -and $entry.Time -le $After.ToUniversalTime()) { continue }
        if ($PSBoundParameters.ContainsKey('Before') -and $entry.Time -ge $Before.ToUniversalTime()) { continue }
        $entry
    }
}
