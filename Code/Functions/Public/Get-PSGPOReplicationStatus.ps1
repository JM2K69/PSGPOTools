function Get-PSGPOReplicationStatus {
    <#
    .SYNOPSIS
        Compares the GPOs of each domain controller of the domain to those of the baseline, as the
        Status tab of the domain in GPMC.
    .DESCRIPTION
        Reads each domain controller: the GPOs of its directory (the group policy containers and
        their versionNumber) and of its SYSVOL (the folders of Policies and the version of their
        GPT.INI), and compares them to the baseline, the domain controller the domain was read
        from: its PDC emulator, where GPMC and the console change the GPOs (Get-PSGPODirectory).
        Active Directory replicates the directory to the other domain controllers, DFSR (Windows)
        their SYSVOL; Samba does not replicate SYSVOL.

        One row per GPO and domain controller, with its State:
        - InSync: the version of the baseline, in the directory and in SYSVOL.
        - DirectoryDiffers: another version in the directory: its replication is not done.
        - SysvolDiffers: SYSVOL does not have the version of the directory (another version, no
          folder or no GPT.INI): its replication is not done, or, on the baseline, a change
          stopped halfway. The computers apply SYSVOL.
        - Missing: the GPO is on the baseline, not in the directory of this domain controller.
        - Extra: the GPO is in the directory of this domain controller, not on the baseline.
        - OrphanFolder: a folder of SYSVOL without a GPO in the directory of this domain controller.
        - Unreachable: the domain controller cannot be read (its directory or its SYSVOL).
        DirectoryVersion, SysvolVersion and BaselineVersion are versionNumber values (user version
        in the high word, computer version in the low word); Detail says it in words.
    .PARAMETER Name
        Display names of the GPOs (wildcards allowed); all the GPOs, and the folders without a GPO,
        by default.
    .PARAMETER Directory
        Directory of the GPOs (Get-PSGPODirectory), read over LDAP: its domain controller is the
        baseline. The domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory: the baseline.
    .PARAMETER DomainController
        Domain controllers to compare to the baseline (DNS names); every domain controller of the
        domain by default.
    .EXAMPLE
        Get-PSGPOReplicationStatus | Where-Object State -NE 'InSync' | Format-Table DomainController, DisplayName, State, Detail -Wrap
    .EXAMPLE
        Get-PSGPOReplicationStatus -Name 'Default Domain Policy' -DomainController dc2.contoso.com
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgporeplicationstatus/
    .LINK
        Test-PSGPOHealth
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.ReplicationStatus')]
    param(
        [Parameter(ValueFromPipeline)]
        [string[]]$Name,

        [GPOToolsDirectory]$Directory,

        [string]$Server,

        [string[]]$DomainController
    )

    begin {
        $names = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($item in $Name) { $names.Add($item) }
    }
    end {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        if ($Directory -isnot [GPOToolsLdapDirectory]) { throw 'The replication of the GPOs is read on the domain controllers: give a directory read over LDAP (Get-PSGPODirectory).' }
        $data = Get-PSGPOHealthData -Directory $Directory -DomainController $DomainController -Name $names
        $data.Replication
    }
}
