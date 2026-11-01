<#
    Copy... (the context menu of a GPO or of a link to it), as Copy and Paste of GPMC: a new GPO
    of the domain with the settings, the status, the WMI filter and the comment of the GPO
    (Copy-PSGPOContent, as Copy-PSGPO), not its links; the permissions of a new GPO, or those of
    the GPO (Preserve the existing permissions). Made in the background: the files of the GPO are
    read and written.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerCopyView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerCopyView {
    $gpoCopy = @{ Source = $null }

    function Open-GpoCopyForm {
        $gpo = Get-SelectedGpo
        if (-not $gpo) { return }
        $gpoCopy.Source = $gpo
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $gpoCopyTitleTextBlock.Text = Get-PSGPOText "Copy the GPO '{0}' to a new GPO of {1}: its settings, its status, its WMI filter and its comment, not its links" $gpo.DisplayName $Directory.DomainName
        $gpoCopyNameTextBox.Text = Get-PSGPOText 'Copy of {0}' $gpo.DisplayName
        # A GPO of a creator waits for its approval: the approval gives its permissions.
        $creator = $Directory.IsWorkflowCreator()
        $gpoCopyPermissionComboBox.SelectedIndex = 0
        $gpoCopyPermissionComboBox.IsEnabled = -not $creator
        $gpoCopyPermissionTextBlock.Text = if ($creator) { Get-PSGPOText 'It waits for the approval of {0}, which gives its permissions: it applies to nobody until then.' ($Directory.Workflow.Approvers -join ', ') } else { '' }
        $gpoCopyErrorTextBlock.Text = ''
        Show-DirectoryForm $gpoCopyPanel
        $null = $gpoCopyNameTextBox.Focus()
        $gpoCopyNameTextBox.SelectAll()
    }

    function Submit-GpoCopy {
        $source = $gpoCopy.Source
        $name = "$($gpoCopyNameTextBox.Text)".Trim()
        if (-not $source) { return }
        if (-not $name) { $gpoCopyErrorTextBlock.Text = Get-PSGPOText 'The GPO name is required.'; return }
        if ($Directory.FindGpo($name)) { $gpoCopyErrorTextBlock.Text = Get-PSGPOText "A GPO named '{0}' already exists in {1}." $name $Directory.DomainName; return }
        $gpoCopyErrorTextBlock.Text = ''
        $copyAcl = $gpoCopyPermissionComboBox.SelectedIndex -eq 1
        $null = Start-ConsoleOperation -NoCancel -Text (Get-PSGPOText "Copying the GPO '{0}'..." $source.DisplayName) -ScriptBlock {
            param($Directory, $Source, $Name, $CopyAcl)
            $new = $Directory.NewGpo($Name)
            $problem = $null
            $skipped = @()
            try { $skipped = @(Copy-PSGPOContent -Directory $Directory -Source $Source -Target $new -CopyAcl:$CopyAcl) } catch { $problem = $_.Exception.GetBaseException().Message }
            [pscustomobject]@{ Gpo = $new; Skipped = $skipped; Problem = $problem }
        } -ArgumentList $Directory, $source, $name, $copyAcl -Done {
            param($Result)
            $copy = @($Result)[0]
            $gpoCopyPanel.IsVisible = $false
            Update-DirectoryTree -Select $copy.Gpo
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add((Get-PSGPOText "GPO '{0}' created, a copy of '{1}': link it where it applies." $copy.Gpo.DisplayName $gpoCopy.Source.DisplayName))
            if ($copy.Gpo.ApprovalState -eq 'Pending') { $lines.Add((Get-PSGPOText 'It waits for the approval of {0}: it applies to nobody until then.' ($Directory.Workflow.Approvers -join ', '))) }
            if (@($copy.Skipped).Count) {
                $lines.Add((Get-PSGPOText 'Permissions not copied, given in the Delegation tab if they are needed: {0}' (@(foreach ($row in $copy.Skipped) { Get-PSGPOCopySkippedText -Row $row }) -join ', ')))
            }
            if ($copy.Problem) { $lines.Add((Get-PSGPOText 'It is created, but not completed: {0}' $copy.Problem)) }
            Show-DirectoryResult -Text ($lines -join [Environment]::NewLine) -Problem:([bool]$copy.Problem)
        } -Failed {
            param($ErrorRecord)
            $gpoCopyErrorTextBlock.Text = $ErrorRecord.Exception.GetBaseException().Message
        }
    }

    $gpoCopyMenuItem.Add_Click({ Open-GpoCopyForm })
    $gpoCopyConfirmButton.Add_Click({ Submit-GpoCopy })
    $gpoCopyCancelButton.Add_Click({ $gpoCopyPanel.IsVisible = $false })
    $gpoCopyNameTextBox.Add_KeyDown({
            param($control, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-GpoCopy; $e.Handled = $true }
            elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $gpoCopyPanel.IsVisible = $false; $e.Handled = $true }
        })
}
