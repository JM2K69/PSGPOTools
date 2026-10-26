function Approve-PSGPO {
    <#
    .SYNOPSIS
        Approves GPOs that wait for their approval (approval workflow).
    .DESCRIPTION
        A GPO a creator (Tier 1) creates waits for its approval: its creator owns it, and it applies
        to nobody. An approver (Tier 0) approves it:

        - its owner becomes the owner of the approved GPOs (Workflow.ApprovedOwner), in the
          directory and in SYSVOL, its folder and every file in it: the creator cannot give itself
          its rights back;
        - the creator and the groups of creators lose their rights; the groups of creators of the
          creator keep editing its settings (-CreatorRights EditSettings: each change makes it
          differ from its approved version, Get-PSGPODrift) or only read it (ReadOnly);
        - it applies to -ApplyTo and is denied to -DenyTo; with -CreateFilteringGroups, to its new
          groups APPLY_<GPO> and DENY_<GPO> (the prefixes, scope and container of the
          configuration: NewGpo.SecurityFilteringGroups), created first by the approver: a GPO
          whose groups cannot be created is not approved. Without them, the GPO applies to its
          groups APPLY_<GPO> and DENY_<GPO> when they exist, else to Authenticated Users;
        - it is backed up with the approved label (Backup.ApprovedLabel), in -BackupPath.

        Whoever manages the members of the group that applies the GPO decides where it applies:
        the groups the approver creates are its own.
    .PARAMETER Name
        Display names of the GPOs (wildcards allowed).
    .PARAMETER CreatorRights
        What the creators may still do with the GPO: ReadOnly or EditSettings; by default the one
        of the configuration (Workflow.CreatorRights).
    .PARAMETER ApplyTo
        The group of the domain that applies the GPO; by default its group APPLY_<GPO> when it
        exists, else Authenticated Users.
    .PARAMETER DenyTo
        A group of the domain the GPO is denied to; by default its group DENY_<GPO> when it exists.
    .PARAMETER CreateFilteringGroups
        Creates the groups APPLY_<GPO> and DENY_<GPO>, and the GPO applies to the first and is
        denied to the second.
    .PARAMETER GroupContainer
        Where -CreateFilteringGroups creates the groups; by default the container of the
        configuration (NewGpo.SecurityFilteringGroups.Container), else the users container.
    .PARAMETER BackupPath
        Root folder of the backups; by default the one of the History tab of the window.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Approve-PSGPO -Name 'T1 - Servers - Proxy' -ApplyTo 'APPLY_T1 - Servers - Proxy'
    .EXAMPLE
        Approve-PSGPO -Name 'T1 - Servers - Proxy' -CreateFilteringGroups -GroupContainer 'OU=Groups,OU=Tier 1'
    .EXAMPLE
        Approve-PSGPO -Name 'T1 - *' -CreatorRights EditSettings
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/approve-psgpo/
    .LINK
        Initialize-PSGPOWorkflow
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Name,

        [ValidateSet('ReadOnly', 'EditSettings')]
        [string]$CreatorRights,

        [string]$ApplyTo,

        [string]$DenyTo,

        [switch]$CreateFilteringGroups,

        [string]$GroupContainer,

        [string]$BackupPath,

        [GPOToolsDirectory]$Directory,

        [string]$Server
    )

    begin {
        if (-not $Directory) {
            $read = @{}
            if ($Server) { $read.Server = $Server }
            $Directory = Get-PSGPODirectory @read -ErrorAction Stop
        }
        Use-PSGPODomainConfiguration -Directory $Directory
        if (-not $CreatorRights) { $CreatorRights = (Get-PSGPOWorkflowSetting).CreatorRights }
        if (-not $BackupPath) { $BackupPath = Get-PSGPODefaultBackupPath }
        if ($CreateFilteringGroups -and ($ApplyTo -or $DenyTo)) { throw '-CreateFilteringGroups gives the GPO its own groups: do not give -ApplyTo or -DenyTo with it.' }
        if ($GroupContainer -and -not $CreateFilteringGroups) { throw '-GroupContainer is where -CreateFilteringGroups creates the groups.' }
        $givenApply = if ($ApplyTo) { Resolve-PSGPOApplyTo -Directory $Directory -Name $ApplyTo }
        $givenDeny = if ($DenyTo) { Resolve-PSGPOApplyTo -Directory $Directory -Name $DenyTo }
    }
    process {
        foreach ($pattern in $Name) {
            $found = @($Directory.Gpos | Where-Object { Test-PSGPONameMatch -Name $_.DisplayName -Pattern $pattern })
            if (-not $found) { Write-Error "No GPO named '$pattern' in $($Directory.DomainName)."; continue }
            foreach ($gpo in $found) {
                if ($gpo.ApprovalState -ne 'Pending') { Write-Error "The GPO '$($gpo.DisplayName)' does not wait for an approval."; continue }
                # Who applies it: what is given, its own groups, else Authenticated Users.
                $apply = $givenApply
                $deny = $givenDeny
                if (-not $CreateFilteringGroups -and -not $ApplyTo) {
                    $existing = Find-PSGPOFilteringGroup -Directory $Directory -Gpo $gpo
                    # A group of its name someone else made: never Authenticated Users in its place.
                    if ($existing.Problem) { Write-Error "The GPO '$($gpo.DisplayName)' is not approved: $($existing.Problem) Give -ApplyTo, or -CreateFilteringGroups once it is deleted."; continue }
                    $apply =if ($existing.Apply) { $existing.Apply } else { Resolve-PSGPOApplyTo -Directory $Directory -Name 'Authenticated Users' }
                    if (-not $DenyTo -and $existing.Deny) { $deny = $existing.Deny }
                }
                # What is approved: the GPO as it is now, before the confirmation; refused if it changes.
                try { $stamp = Get-PSGPOReviewStamp -Directory $Directory -Gpo $gpo }
                catch { Write-Error "The GPO '$($gpo.DisplayName)' is not approved: it cannot be read ($($_.Exception.GetBaseException().Message))."; continue }
                $who = if ($CreateFilteringGroups) { 'applied by its new groups APPLY_ and DENY_' } else { "applied by $($apply.Name)$(if ($deny) { ", denied to $($deny.Name)" })" }
                if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", "Approve it: owned by $($Directory.Workflow.ApprovedOwner), the creators $(if ($CreatorRights -eq 'EditSettings') { 'edit its settings' } else { 'read it' }), $who")) { continue }
                try {
                    Invoke-PSGPOApproval -Directory $Directory -Gpo $gpo -CreatorRights $CreatorRights -ApplyTo $apply -DenyTo $deny `
                        -CreateFilteringGroups:$CreateFilteringGroups -GroupContainer $GroupContainer -BackupPath $BackupPath -ReviewStamp $stamp
                } catch {
                    Write-Error "The GPO '$($gpo.DisplayName)' is not approved: $($_.Exception.GetBaseException().Message)"
                }
            }
        }
    }
}
