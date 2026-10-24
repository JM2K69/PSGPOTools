function Get-PSGPOPolicyRuleSet {
    <#
    .SYNOPSIS
        Reads rule sets of Policy Analyzer (.PolicyRules), or makes one from GPOs.
    .DESCRIPTION
        A rule set holds the settings of one or more GPOs, as the Policy Analyzer of the
        Microsoft Security Compliance Toolkit keeps them in a .PolicyRules file: the registry
        settings of their Registry.pol files (computer and user), their security template
        (GptTmpl.inf), their advanced audit policy (audit.csv) and their client-side extensions.

        It is read from .PolicyRules files (those of the security baselines of Microsoft, or of
        Policy Analyzer), or made from GPOs: of the domain, of backups of HGPM (Get-PSGPOBackup)
        or of GPMC (the GPOs folder of a security baseline), as GPO2PolicyRules.exe does.
        Compare-PSGPOPolicyRuleSet compares sets, Export-PSGPOPolicyRuleSet saves one.

        With -Container, the set is made of the GPOs that apply to a domain or an OU, in their
        order of precedence as the Group Policy Inheritance tab of GPMC lists them (the enforced
        links first, from the domain down, then the others from the OU up until an OU that blocks
        the inheritance; the links disabled and the parts a GPO status disables left out): each
        setting then has the precedence of its GPO, and Compare-PSGPOPolicyRuleSet shows the value
        that wins. The security filtering, the WMI filters and the loopback processing are those of
        each computer or user, not taken into account.
    .PARAMETER Path
        Files of Policy Analyzer (.PolicyRules), or folders: the .PolicyRules files they hold.
        One set per file, named after it.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern): of the domain, or of the backups of
        -GpmcBackupPath (all of them by default).
    .PARAMETER Backup
        Backups of HGPM (Get-PSGPOBackup).
    .PARAMETER GpmcBackupPath
        A folder of backups (alias -BackupPath): of GPMC (Backup-GPO, the GPOs folder of a security
        baseline, or one backup), or of HGPM (the folder of Backup-PSGPO, the newest backup of each
        GPO; the folder of a GPO; one backup, or its Files folder).
    .PARAMETER Container
        A domain or an OU: its distinguished name, the name of the domain, or the name of an OU when
        only one OU has it. The set holds the GPOs that apply to it, by precedence.
    .PARAMETER SetName
        Name of the set made from GPOs: by default the name of the GPO when there is one, else
        the name of the domain or of the folder; "<OU> (precedence)" with -Container.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOPolicyRuleSet -Path "$HOME\Documents\PolicyAnalyzer"
    .EXAMPLE
        Get-PSGPOPolicyRuleSet -Name 'Tier 1 - Servers*' -SetName 'Production'
    .EXAMPLE
        Get-PSGPOPolicyRuleSet -GpmcBackupPath '.\Windows 11 v25H2 Security Baseline\GPOs'
    .EXAMPLE
        # What the computers of an OU get, against the baseline of Microsoft
        $ou = Get-PSGPOPolicyRuleSet -Container 'OU=Workstations,DC=contoso,DC=com'
        Compare-PSGPOPolicyRuleSet -RuleSet (Get-PSGPOPolicyRuleSet .\MSFT-Win11-v25H2.PolicyRules), $ou -DifferenceOnly
    .EXAMPLE
        Get-PSGPOBackup -Path /srv/gpo-backups -Name 'Default Domain Policy' | Select-Object -First 1 | Get-PSGPOPolicyRuleSet
    .OUTPUTS
        GPOToolsPolicyRuleSet
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpopolicyruleset/
    .LINK
        Compare-PSGPOPolicyRuleSet
    .LINK
        Export-PSGPOPolicyRuleSet
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    [OutputType([GPOToolsPolicyRuleSet])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'File')]
        [string[]]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Domain')]
        [Parameter(ParameterSetName = 'Gpmc')]
        [string[]]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Backup')]
        [PSTypeName('PSGPOTools.Backup')]
        [object[]]$Backup,

        [Parameter(Mandatory, ParameterSetName = 'Gpmc')]
        [Alias('BackupPath')]
        [string]$GpmcBackupPath,

        [Parameter(Mandatory, ParameterSetName = 'Container')]
        [string]$Container,

        [Parameter(ParameterSetName = 'Domain')]
        [Parameter(ParameterSetName = 'Backup')]
        [Parameter(ParameterSetName = 'Gpmc')]
        [Parameter(ParameterSetName = 'Container')]
        [string]$SetName,

        [Parameter(ParameterSetName = 'Domain')]
        [Parameter(ParameterSetName = 'Container')]
        [GPOToolsDirectory]$Directory,

        [Parameter(ParameterSetName = 'Domain')]
        [Parameter(ParameterSetName = 'Container')]
        [string]$Server
    )

    begin {
        $backups = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Backup') { foreach ($item in $Backup) { $backups.Add($item) } }
    }
    end {
        switch ($PSCmdlet.ParameterSetName) {
            'File' {
                foreach ($item in $Path) {
                    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($item)
                    $files = if (Test-Path -LiteralPath $full -PathType Container) {
                        @(Get-ChildItem -LiteralPath $full -File -Filter '*.PolicyRules' | Sort-Object Name)
                    } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
                        @(Get-Item -LiteralPath $full)
                    } else {
                        Write-Error "No .PolicyRules file or folder: $item"
                        continue
                    }
                    foreach ($file in $files) {
                        try {
                            $set = [GPOToolsPolicyRuleSet]::Parse([System.IO.File]::ReadAllBytes($file.FullName), [System.IO.Path]::GetFileNameWithoutExtension($file.Name))
                            $set.Path = $file.FullName
                            $set
                        } catch {
                            Write-Error "$($file.FullName) is not read: $($_.Exception.GetBaseException().Message)"
                        }
                    }
                }
            }
            'Container' {
                if (-not $Directory) {
                    $read = @{}
                    if ($Server) { $read.Server = $Server }
                    $Directory = Get-PSGPODirectory @read -ErrorAction Stop
                }
                New-PSGPOPolicyRuleSetFromSom -Directory $Directory -Som (Resolve-PSGPOSom -Directory $Directory -Target $Container) -SetName $SetName
            }
            'Domain' {
                if (-not $Directory) {
                    $read = @{}
                    if ($Server) { $read.Server = $Server }
                    $Directory = Get-PSGPODirectory @read -ErrorAction Stop
                }
                $gpos = @(Find-PSGPOByName -Directory $Directory -Name $Name)
                if (-not $gpos.Count) { return }
                New-PSGPOPolicyRuleSetFromGpo -Directory $Directory -Gpo $gpos -SetName $SetName
            }
            'Backup' {
                if (-not $backups.Count) { return }
                $set = [GPOToolsPolicyRuleSet]::new($(if ($SetName) { $SetName } elseif ($backups.Count -eq 1) { $backups[0].DisplayName } else { 'Backups' }))
                $set.Path = if ($backups.Count -eq 1) { $backups[0].Path } else { Split-Path -Path $backups[0].Path -Parent }
                foreach ($item in $backups) {
                    $files = Read-PSGPOBackupFile -Backup $item
                    foreach ($rule in @(ConvertTo-PSGPOPolicyRule -Files $files -PolicyName $item.DisplayName -SourceRoot (Join-Path $item.Path 'Files'))) { $set.Rules.Add($rule) }
                    $extensions = Get-PSGPOBackupExtensionName -Backup $item -Files $files
                    Add-PSGPOPolicyRuleExtension -RuleSet $set -MachineExtensionNames $extensions.Machine -UserExtensionNames $extensions.User
                }
                $set
            }
            'Gpmc' {
                $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($GpmcBackupPath)
                New-PSGPOPolicyRuleSetFromBackupFolder -Path $full -Name $Name -SetName $SetName
            }
        }
    }
}
