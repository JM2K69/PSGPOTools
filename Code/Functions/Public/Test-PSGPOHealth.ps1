function Test-PSGPOHealth {
    <#
    .SYNOPSIS
        Checks the GPOs of the domain as GPMC and gpotool: their folder and version in SYSVOL,
        their client-side extensions, the links, and their replication on every domain controller.
    .DESCRIPTION
        Returns one row per problem found, nothing when there is none. Severity, Check, Target (a
        GPO, a folder, an OU or a domain controller), Id of the GPO, DomainController and Detail:

        - Error, Redirected: the gPCFileSysPath of the GPO is not its folder in SYSVOL.
        - Error, Folder: the GPO has no folder in SYSVOL, or no GPT.INI with a version: the
          computers fail to apply it.
        - Error, Version: the versions of the GPO in the directory and in SYSVOL differ: a change
          stopped halfway, and the computers apply SYSVOL.
        - Warning, Extension: a file of the GPO holds settings (Registry.pol, GptTmpl.inf,
          audit.csv, scripts.ini, the preferences) whose client-side extension the GPO does not
          declare (gPCMachineExtensionNames, gPCUserExtensionNames): they are not applied.
        - Warning, OrphanFolder: a folder of SYSVOL without a GPO in the directory.
        - Warning, Link: a link to a GPO of the domain that does not exist.
        - Warning, Replication: another domain controller does not have the GPO, or not the same
          version, in its directory or in its SYSVOL (Get-PSGPOReplicationStatus).
        - Warning, DomainController: a domain controller that cannot be read.

        The GPOs are checked on the baseline, the domain controller the domain was read from: its
        PDC emulator, as GPMC (Get-PSGPODirectory). The other domain controllers are compared to it.
    .PARAMETER Name
        Display names of the GPOs (wildcards allowed); all the GPOs, the folders without a GPO and
        the links, by default.
    .PARAMETER Directory
        Directory of the GPOs (Get-PSGPODirectory), read over LDAP: its domain controller is the
        baseline. The domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory: the baseline.
    .PARAMETER DomainController
        Domain controllers to compare to the baseline (DNS names); every domain controller of the
        domain by default.
    .EXAMPLE
        Test-PSGPOHealth | Format-Table Severity, Check, Target, DomainController, Detail -Wrap
    .EXAMPLE
        # Nothing returned: no problem
        if (-not (Test-PSGPOHealth -Server dc.hardenbox.labo)) { 'The GPOs are healthy.' }
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/test-psgpohealth/
    .LINK
        Get-PSGPOReplicationStatus
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.HealthFinding')]
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
        if ($Directory -isnot [GPOToolsLdapDirectory]) { throw 'The GPOs are checked on the domain controllers: give a directory read over LDAP (Get-PSGPODirectory).' }
        $data = Get-PSGPOHealthData -Directory $Directory -DomainController $DomainController -Name $names
        $data.Findings
    }
}
