function Test-PSGPOSecurityPosture {
    <#
    .SYNOPSIS
        Checks who can create, change and link the GPOs of the domain beyond the Tier 0 and the
        approval workflow, and who owns the folders of SYSVOL the computers and the consoles read.
    .DESCRIPTION
        Returns one row per finding, the most severe first, nothing when there is none. Severity,
        Check, Target, Principal (the account found) and Detail:

        - High, GroupPolicyCreatorOwners: a member of Group Policy Creator Owners outside of the
          Tier 0 creates GPOs, and owns them, outside of the approval workflow (Medium when the
          workflow is off).
        - High, GpoCreation: an account outside of the Tier 0 and of the creators of the workflow
          creates GPOs in CN=Policies, or changes who can (its DACL, its owner).
        - High, GpoEditableByAll: a group of every account (Everyone, Authenticated Users, Domain
          Users...) can change a GPO, or owns it.
        - High, Tier0Gpo: an account outside of the Tier 0 can change, or owns, a GPO linked to the
          domain or to the domain controllers OU: it controls the domain controllers.
        - High, LinkByAll and Tier0Link: a group of every account can link GPOs (gPLink,
          gPOptions) somewhere; an account outside of the Tier 0 can link them to the domain or to
          the domain controllers OU.
        - High, PoliciesFolder, CentralStore and ConfigurationFolder: an account outside of the
          Tier 0 owns or can change the Policies folder of SYSVOL, the central store
          (Policies\PolicyDefinitions, the ADMX files every console reads) or the configuration of
          HGPM (SYSVOL\<domain>\PSGPOTools). The creators of the workflow create folders in
          Policies, this folder only: expected. Medium: there is no central store while the
          creators create folders in Policies (one of them could create it), or a folder cannot
          be read.
        - High, Configuration and WorkflowRoles: a role of the workflow names no account of the
          domain, or the roles overlap (Test-PSGPOWorkflowRole).
        - Low, Workflow, AuditLog and SystemLog: the approval workflow is off, there is no central
          audit log, nothing goes to the log of the system.

        The Tier 0 is Administrator, the domain controllers, SYSTEM, the groups the domain protects
        (AdminSDHolder: Domain Admins, Enterprise Admins, Schema Admins, Key Admins, Enterprise Key
        Admins, Administrators, Account, Server, Print and Backup Operators), the approvers of the
        workflow and the owner of the approved GPOs, and the accounts in their groups (nested ones
        included). Group Policy Creator Owners keeps the rights the domain gives it: its members are
        the finding.

        It only reads the directory and SYSVOL: an account of no group can run it, as a group
        managed service account in a scheduled task (Linux: a keytab).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory), read over LDAP; the domain is read when not
        given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .PARAMETER SystemLog
        Also sends the findings to the log of the system, for a SIEM, when Log.SystemLog is on:
        a summary (event 4000: Information, Warning when a finding is High) and each High finding
        (event 4001, Warning). Windows: the source HGPM (Register-PSGPOEventSource); Linux: syslog,
        tag hgpm.
    .EXAMPLE
        Test-PSGPOSecurityPosture | Format-Table Severity, Check, Target, Principal -AutoSize
    .EXAMPLE
        # A daily task, as a gMSA: the High findings to the SIEM
        Test-PSGPOSecurityPosture -Server dc1.contoso.com -SystemLog | Out-Null
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/test-psgposecurityposture/
    .LINK
        Initialize-PSGPOWorkflow
    .LINK
        Test-PSGPOHealth
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.PostureFinding')]
    param(
        [GPOToolsDirectory]$Directory,

        [string]$Server,

        [switch]$SystemLog
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    if ($Directory -isnot [GPOToolsLdapDirectory]) { throw 'The posture is that of a domain: give a directory read over LDAP (Get-PSGPODirectory).' }
    Use-PSGPODomainConfiguration -Directory $Directory
    $findings = Get-PSGPOPostureData -Directory $Directory
    if ($SystemLog) {
        $high = @($findings | Where-Object { $_.Severity -eq 'High' })
        $count = { param([string]$Severity) @($findings | Where-Object { $_.Severity -eq $Severity }).Count }
        $summary = "HGPM posture of $($Directory.DomainName): $(& $count 'High') high, $(& $count 'Medium') medium, $(& $count 'Low') low."
        Write-PSGPOSystemLog -Level $(if ($high.Count) { 'Warning' } else { 'Information' }) -EventId 4000 -Message $summary
        foreach ($finding in $high) {
            Write-PSGPOSystemLog -Level Warning -EventId 4001 -Message "HGPM posture of $($Directory.DomainName), $($finding.Check): $($finding.Target)$(if ($finding.Principal) { " - $($finding.Principal)" }): $($finding.Detail)"
        }
    }
    $findings
}
