function Initialize-PSGPOWorkflow {
    <#
    .SYNOPSIS
        Delegates the creation of GPOs to the creators of the approval workflow, and checks it.
    .DESCRIPTION
        The approval workflow (Workflow in the configuration of the domain: Get-PSGPOConfiguration)
        lets the creators (Tier 1 groups) create GPOs that wait for the approval of an approver
        (Tier 0). They need two rights, and not Group Policy Creator Owners, which would let them
        create GPOs outside the workflow:

        - in the directory, CN=Policies,CN=System: create groupPolicyContainer objects; the
          creator owns the GPO it creates and gets full control of it (CREATOR OWNER of the
          class), until it is approved;
        - in SYSVOL, the Policies folder: list, read and create folders (this folder only), and
          CREATOR OWNER full control of the folders and files it creates.

        The central store (Policies\PolicyDefinitions, the ADMX files every console reads) must
        exist before: a creator that creates folders in Policies could create it, and own it. It
        is not created here, as an empty central store hides the administrative templates of
        GPMC: create it with Install-PSGPOAdmx -CentralStore, or a copy of a PolicyDefinitions
        folder. Without it, -Apply changes nothing and stops with an error that says why; when the
        creators create folders already, it warns. Its last row says whether the Tier 0 owns it.

        Without -Apply, it says what is there and what is missing; with it, an administrator of
        the domain adds what is missing. One row per right: Target, Account, Right, State
        (Present, Added or Missing). Run it again after samba-tool ntacl sysvolreset, which gives
        SYSVOL its default ACL back.
    .PARAMETER Apply
        Adds the rights that are missing.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Initialize-PSGPOWorkflow -Server dc1.contoso.com
    .EXAMPLE
        Initialize-PSGPOWorkflow -Apply
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/initialize-psgpoworkflow/
    .LINK
        Approve-PSGPO
    .LINK
        Get-PSGPOConfiguration
    .LINK
        Test-PSGPOSecurityPosture
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$Apply,

        [GPOToolsDirectory]$Directory,

        [string]$Server
    )

    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    if ($Directory -isnot [GPOToolsLdapDirectory]) { throw 'The delegation is that of a domain: read it with Get-PSGPODirectory.' }
    Use-PSGPODomainConfiguration -Directory $Directory
    $doApply = $Apply -and $PSCmdlet.ShouldProcess("CN=Policies and the Policies folder of SYSVOL in $($Directory.DomainName)", 'Delegate the creation of GPOs to the creators of the approval workflow')
    Set-PSGPODomainWorkflowDelegation -Directory $Directory -Apply:$doApply
}
