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
    .PARAMETER Path
        Files of Policy Analyzer (.PolicyRules), or folders: the .PolicyRules files they hold.
        One set per file, named after it.
    .PARAMETER Name
        Display names of the GPOs (* and ? make a pattern): of the domain, or of the GPMC backups
        of -GpmcBackupPath (all of them by default).
    .PARAMETER Backup
        Backups of HGPM (Get-PSGPOBackup).
    .PARAMETER GpmcBackupPath
        A folder of GPMC backups (Backup-GPO, the GPOs folder of a security baseline), or one backup.
    .PARAMETER SetName
        Name of the set made from GPOs: by default the name of the GPO when there is one, else
        the name of the domain or of the folder.
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
        [string]$GpmcBackupPath,

        [Parameter(ParameterSetName = 'Domain')]
        [Parameter(ParameterSetName = 'Backup')]
        [Parameter(ParameterSetName = 'Gpmc')]
        [string]$SetName,

        [Parameter(ParameterSetName = 'Domain')]
        [GPOToolsDirectory]$Directory,

        [Parameter(ParameterSetName = 'Domain')]
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
                $entries = @(Get-PSGPOGpmcBackupEntry -Path $full | Where-Object { $entry = $_; -not $Name -or @($Name | Where-Object { Test-PSGPONameMatch -Name $entry.DisplayName -Pattern $_ }).Count })
                if (-not $entries.Count) { throw "No GPMC backup$(if ($Name) { " of '$($Name -join "', '")'" }) in $GpmcBackupPath." }
                # As GPO2PolicyRules: the GPOs by name, the newest backup of each.
                $entries = @($entries | Group-Object Id | ForEach-Object { $_.Group[0] } | Sort-Object DisplayName)
                $set = [GPOToolsPolicyRuleSet]::new($(if ($SetName) { $SetName } elseif ($entries.Count -eq 1) { $entries[0].DisplayName } else { Split-Path -Path $full -Leaf }))
                $set.Path = $full
                foreach ($entry in $entries) {
                    $root = Join-Path $entry.Path 'DomainSysvol' 'GPO'
                    foreach ($rule in @(ConvertTo-PSGPOPolicyRule -Files (Read-PSGPOGpmcBackupFile -Backup $entry) -PolicyName $entry.DisplayName -SourceRoot $root)) { $set.Rules.Add($rule) }
                    Add-PSGPOPolicyRuleExtension -RuleSet $set -MachineExtensionNames $entry.MachineExtensionNames -UserExtensionNames $entry.UserExtensionNames
                }
                $set
            }
        }
    }
}
