function Get-PSGPOProductAdmx {
    <#
    .SYNOPSIS
        Lists the products whose ADMX files Install-PSGPOProductAdmx installs: their publisher, the version pinned, their languages.
    .DESCRIPTION
        The module pins one package of each product (Resources/AdmxProducts.json): its address on
        the site of its publisher, its size and SHA-256, and the SHA-256 of each of its .admx and
        of its .adml files. Install-PSGPOProductAdmx installs only that package, those files. A
        newer version of a product than the one pinned is installed from its folder with
        -SourcePath.
    .PARAMETER Name
        The products to show (Office, Firefox...); all of them by default.
    .EXAMPLE
        Get-PSGPOProductAdmx | Format-Table Name, Publisher, Version, Languages
    .EXAMPLE
        (Get-PSGPOProductAdmx -Name Firefox).Languages
    .OUTPUTS
        PSGPOTools.AdmxProduct
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpoproductadmx/
    .LINK
        Install-PSGPOProductAdmx
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.AdmxProduct')]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name
    )

    $catalog = @(Get-PSGPOAdmxProductCatalog)
    foreach ($product in @(Get-PSGPOAdmxProductCatalog -Name $Name)) {
        $admx = @($product.Files | Where-Object { "$($_.Path)" -notmatch '/' } | ForEach-Object Path)
        $own = @(Get-PSGPOAdmxProductOwnFile -Product $product -Catalog $catalog)
        [pscustomobject]@{
            PSTypeName  = 'PSGPOTools.AdmxProduct'
            Name        = $product.Name
            DisplayName = $product.DisplayName
            Publisher   = $product.Publisher
            Version     = $product.Version
            Languages   = @(Get-PSGPOAdmxProductLanguage -Product $product)
            AdmxFiles   = $admx
            # The .admx files another product pinned holds too (google.admx: Chrome, Google Update).
            Shared      = @($admx | Where-Object { $own -notcontains $_ })
            Files       = @($product.Files).Count
            FileName    = $product.FileName
            Size        = $product.Size
            Page        = $product.Page
            Uri         = $product.Uri
        }
    }
}
