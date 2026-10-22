<#
    A certificate store of the public key policies in the tree of the policy editor (Security
    Settings > Public Key Policies > Trusted Root Certification Authorities...): the store of the
    Registry.pol of a scope (PSGPOPublicKeyPolicy.ps1).
#>

class GPOToolsCertificateStoreNode {
    # Machine or User
    [string]$Scope
    # The name of the store under Software\Policies\Microsoft\SystemCertificates (Root, EFS...)
    [string]$Store
    # Its name in the Group Policy editor
    [string]$Name

    GPOToolsCertificateStoreNode([string]$Scope, [string]$Store, [string]$Name) {
        $this.Scope = $Scope
        $this.Store = $Store
        $this.Name = $Name
    }

    [string] ToString() { return "$($this.Name) ($($this.Scope))" }
}
