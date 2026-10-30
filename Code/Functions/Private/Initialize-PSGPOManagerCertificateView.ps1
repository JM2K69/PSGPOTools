<#
    The Public Key Policies of the GPO edited: the certificates of a store in its Registry.pol.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerCertificateView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerCertificateView {
    $certificates = @{ Node = $null }
    function Set-CertificateStatus {
        param([string]$Text, [switch]$Problem)
        $certificatesStatusTextBlock.Text = $Text
        if ($Problem) { $certificatesStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $certificatesStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    function Test-CertificateEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $certificates.Node -and $editing.Pol[$certificates.Node.Scope]
    }

    function Update-CertificateToolbar {
        $editable = Test-CertificateEditable
        $certificatesImportButton.IsEnabled = [bool]$editable
        $certificatesPathTextBox.IsEnabled = [bool]$editable
        $certificatesDeleteButton.IsEnabled = $editable -and $certificatesList.SelectedItem
    }

    # The certificates of the store selected in the tree, for the edited GPO.
    function Show-CertificateStore {
        param([GPOToolsCertificateStoreNode]$Node, [string]$Status, [string]$Select)
        $certificates.Node = $Node
        $certificatesDeletePanel.IsVisible = $false
        $scopeLabel = Get-PSGPOText $(if ($Node.Scope -eq 'Machine') { 'Computer Configuration' } else { 'User Configuration' })
        $certificatesTitleTextBlock.Text = "$(Get-PSGPOText $Node.Name) ($scopeLabel)"
        $certificatesInfoTextBlock.Text = (Get-PSGPOText 'In {0}\Registry.pol of the GPO: Software\Policies\Microsoft\SystemCertificates\{1}\Certificates, applied by the Registry extension.' $Node.Scope $Node.Store) +
            $(switch ($Node.Store) {
                    'EFS' { Get-PSGPOText ' The recovery agents of EFS: their certificates also make the EFSBlob, rebuilt at each change.' }
                    'FVE' { Get-PSGPOText ' The data recovery agents of BitLocker (with the policy that gives the identifiers of the organization).' }
                    'FVE_NKP' { Get-PSGPOText ' The certificate of BitLocker Network Unlock.' }
                    'Disallowed' { Get-PSGPOText ' The computers distrust these certificates.' }
                })
        $rows = @()
        $pol = if ($editing.Gpo) { $editing.Pol[$Node.Scope] }
        if (-not $editing.Gpo) {
            $certificatesEmptyTextBlock.Text = Get-PSGPOText 'Edit a GPO (Group Policy Management view) to see and configure its public key policies.'
        } elseif (-not $pol) {
            $certificatesEmptyTextBlock.Text = ''
            if (-not $Status) { $Status = $editing.PolError }
        } else {
            $now = [datetime]::Now
            $rows = @(foreach ($certificate in @(Get-PSGPOPolicyCertificate -Pol $pol -Store $Node.Store)) {
                    $row = [AvaloniaPreferenceRow]::new()
                    $row.Name = $certificate.Subject
                    $row.Summary = if ($certificate.Certificate) {
                        Get-PSGPOText 'Issued by {0} - expires {1} - thumbprint {2}' $certificate.Issuer $certificate.NotAfter.ToString('yyyy-MM-dd') $certificate.Thumbprint
                    } else { Get-PSGPOText 'Thumbprint {0}' $certificate.Thumbprint }
                    $row.Flags = if (-not $certificate.Certificate) { Get-PSGPOText 'This value is not a certificate the console can read.' }
                        elseif ($certificate.NotAfter -lt $now) { Get-PSGPOText 'Expired' }
                    $row.Item = $certificate
                    $row
                })
            $certificatesEmptyTextBlock.Text = if ($rows.Count) { '' } else { Get-PSGPOText 'This GPO has no certificate in this store.' }
        }
        $certificatesEmptyTextBlock.IsVisible = [bool]$certificatesEmptyTextBlock.Text
        $certificatesList.ItemsSource = $rows
        if ($Select) { $certificatesList.SelectedItem = $rows | Where-Object { $_.Item.Thumbprint -eq $Select } | Select-Object -First 1 }
        Set-CertificateStatus $Status
        Update-CertificateToolbar
    }

    # A change of a store: on a copy of the Registry.pol of the scope, written, then kept.
    function Save-CertificateChange {
        param([scriptblock]$Change, [string]$Done, [string]$Select)
        $node = $certificates.Node
        $copy = [GPOToolsRegistryPol]::Parse($editing.Pol[$node.Scope].ToBytes())
        try {
            & $Change $copy
            $efs = @(Get-PSGPOPolicyCertificate -Pol $copy -Store 'EFS').Count -gt 0
            $Directory.WritePublicKeyPolicyFile($editing.Gpo, $node.Scope, $copy.ToBytes(), $efs)
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $editing.Pol[$node.Scope] = $copy
        $settingsCache.Remove("$($editing.Gpo.Id)")
        $version = if ($node.Scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
        Show-CertificateStore -Node $node -Status (Get-PSGPOText '{0} in {1}\Registry.pol (version {2}).' $Done $node.Scope $version) -Select $Select
        $null
    }

    $certificatesList.add_SelectionChanged({ Update-CertificateToolbar })
    $certificatesImportButton.Add_Click({
        $path = "$($certificatesPathTextBox.Text)".Trim().Trim('"')
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { Set-CertificateStatus (Get-PSGPOText 'Give the path of a certificate file (.cer, .crt or .pem).') -Problem; return }
        try { $der = Read-PSGPOCertificateFile -Path $path } catch { Set-CertificateStatus $_.Exception.Message -Problem; return }
        $store = $certificates.Node.Store
        $added = @{ Info = $null }
        $problem = Save-CertificateChange -Done (Get-PSGPOText 'Certificate imported') -Change {
            param($Copy)
            $added.Info = Add-PSGPOPolicyCertificate -Pol $Copy -Store $store -Certificate $der
        }
        if ($problem) { Set-CertificateStatus (Get-PSGPOText 'Not imported: {0}' $problem) -Problem; return }
        $certificatesPathTextBox.Text = ''
        Show-CertificateStore -Node $certificates.Node -Status $certificatesStatusTextBlock.Text -Select $added.Info.Thumbprint
    })
    $certificatesDeleteButton.Add_Click({
        $row = $certificatesList.SelectedItem
        if (-not $row) { return }
        $certificatesDeleteTextBlock.Text = Get-PSGPOText "Delete the certificate '{0}' from the GPO? The computers remove it from their Group Policy store at the next refresh." $row.Name
        $certificatesDeletePanel.IsVisible = $true
    })
    $certificatesDeleteCancelButton.Add_Click({ $certificatesDeletePanel.IsVisible = $false })
    $certificatesDeleteConfirmButton.Add_Click({
        $row = $certificatesList.SelectedItem
        if (-not $row) { return }
        $store = $certificates.Node.Store
        $thumbprint = $row.Item.Thumbprint
        $problem = Save-CertificateChange -Done (Get-PSGPOText "Certificate '{0}' deleted" $row.Name) -Change { param($Copy) Remove-PSGPOPolicyCertificate -Pol $Copy -Store $store -Thumbprint $thumbprint }
        if ($problem) { Set-CertificateStatus (Get-PSGPOText 'Not deleted: {0}' $problem) -Problem }
    })
}
