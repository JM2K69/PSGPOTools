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
        - it applies to -ApplyTo (Authenticated Users by default);
        - it is backed up with the approved label (Backup.ApprovedLabel), in -BackupPath.
    .PARAMETER Name
        Display names of the GPOs (wildcards allowed).
    .PARAMETER CreatorRights
        What the creators may still do with the GPO: ReadOnly or EditSettings; by default the one
        of the configuration (Workflow.CreatorRights).
    .PARAMETER ApplyTo
        The group of the domain that applies the GPO; Authenticated Users by default.
    .PARAMETER BackupPath
        Root folder of the backups; by default the one of the History tab of the window.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Approve-PSGPO -Name 'T1 - Servers - Proxy' -ApplyTo 'APPLY_T1 - Servers - Proxy'
    .EXAMPLE
        Approve-PSGPO -Name 'T1 - *' -CreatorRights EditSettings
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

        [string]$ApplyTo = 'Authenticated Users',

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
        $apply = Resolve-PSGPOApplyTo -Directory $Directory -Name $ApplyTo
    }
    process {
        foreach ($pattern in $Name) {
            $found = @($Directory.Gpos | Where-Object { $_.DisplayName -like $pattern })
            if (-not $found) { Write-Error "No GPO named '$pattern' in $($Directory.DomainName)."; continue }
            foreach ($gpo in $found) {
                if ($gpo.ApprovalState -ne 'Pending') { Write-Error "The GPO '$($gpo.DisplayName)' does not wait for an approval."; continue }
                if (-not $PSCmdlet.ShouldProcess("GPO '$($gpo.DisplayName)'", "Approve it: owned by $($Directory.Workflow.ApprovedOwner), the creators $(if ($CreatorRights -eq 'EditSettings') { 'edit its settings' } else { 'read it' }), applied by $($apply.Name)")) { continue }
                try {
                    Invoke-PSGPOApproval -Directory $Directory -Gpo $gpo -CreatorRights $CreatorRights -ApplyTo $apply -BackupPath $BackupPath
                } catch {
                    Write-Error "The GPO '$($gpo.DisplayName)' is not approved: $($_.Exception.GetBaseException().Message)"
                }
            }
        }
    }
}
