function Import-PSGPOPolicyRuleSet {
    <#
    .SYNOPSIS
        Writes the settings of a rule set (a .PolicyRules file, a security baseline of Microsoft)
        in a GPO of the domain, as LGPO.exe /p applies one to the local policy of a computer.
    .DESCRIPTION
        The registry settings of the set go to the Registry.pol files of the GPO (computer and
        user), its security template to GptTmpl.inf, its advanced audit policy to audit.csv, and
        the GPO declares the client-side extensions they need (those the set lists included: the
        exploit protection, LAPS...). The version of the GPO increases: the computers apply it
        again. On Windows and on Linux, for Active Directory and Samba AD.

        By default the settings are merged: a setting of the set replaces the same setting of the
        GPO, its other settings stay. With -Replace, the registry settings, the security template
        and the audit policy of the GPO are those of the set alone. The other files of the GPO
        (preferences, scripts) never change, nor its links, status and permissions.

        The GPO is backed up first (Backup-PSGPO), unless -NoBackup. A setting the GPOs of the set
        give different values is written with the value of the last one, after a warning.
    .PARAMETER RuleSet
        The set (Get-PSGPOPolicyRuleSet).
    .PARAMETER TargetName
        Display name of the GPO.
    .PARAMETER PolicyName
        Only the settings of these GPOs of the set (* and ? make a pattern); all of them by default.
    .PARAMETER Replace
        The registry settings, security template and audit policy of the GPO replaced by those of
        the set, instead of merged.
    .PARAMETER CreateIfNeeded
        Creates the GPO when the domain does not have it.
    .PARAMETER BackupPath
        Folder of the backup of the GPO before the change; the folder of the backups of the console
        by default.
    .PARAMETER NoBackup
        Changes the GPO without backing it up first.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOPolicyRuleSet -Path .\MSFT-Win11-v25H2.PolicyRules |
            Import-PSGPOPolicyRuleSet -TargetName 'Workstations - Baseline' -PolicyName '*- Computer' -CreateIfNeeded
    .EXAMPLE
        $baseline = Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows Server 2025 Security Baseline\GPOs'
        Import-PSGPOPolicyRuleSet -RuleSet $baseline -TargetName 'Servers - Baseline' -Replace -WhatIf
    .OUTPUTS
        PSGPOTools.PolicyRuleImport
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/import-psgpopolicyruleset/
    .LINK
        Get-PSGPOPolicyRuleSet
    .LINK
        Import-PSGPO
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.PolicyRuleImport')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [GPOToolsPolicyRuleSet]$RuleSet,
        [Parameter(Mandatory)] [string]$TargetName,
        [string[]]$PolicyName,
        [switch]$Replace,
        [switch]$CreateIfNeeded,
        [string]$BackupPath,
        [switch]$NoBackup,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    process {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        $import = @{ Directory = $Directory; RuleSet = $RuleSet; TargetName = $TargetName; Replace = $Replace; CreateIfNeeded = $CreateIfNeeded; NoBackup = $NoBackup }
        if ($PolicyName) { $import.PolicyName = $PolicyName }
        if ($BackupPath) { $import.BackupPath = $BackupPath }
        $rules = @(Select-PSGPOPolicyRuleToImport -RuleSet $RuleSet -PolicyName $PolicyName)
        $gpo = $Directory.FindGpo($TargetName)
        if (-not $gpo -and -not $CreateIfNeeded) { throw "No GPO named '$TargetName' in $($Directory.DomainName): give -CreateIfNeeded to create it." }
        $what = "{0} {1} settings of the rule set '{2}'" -f $(if ($Replace) { 'replace its settings by the' } else { 'write the' }), $rules.Count, $RuleSet.Name
        if (-not $PSCmdlet.ShouldProcess("GPO '$TargetName' of $($Directory.DomainName)", $what)) { return }
        Invoke-PSGPOPolicyRuleImport @import
    }
}
