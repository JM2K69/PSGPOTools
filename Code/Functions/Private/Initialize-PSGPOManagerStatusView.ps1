<#
    The Status tab of the domain, as GPMC: the GPOs of each domain controller compared to the
    baseline (the domain controller read), and their problems. Read on Detect Now only: it reads
    every domain controller.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerStatusView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerStatusView {
    $healthStatus = @{ Data = $null; Running = $false }
    function Update-StatusTab {
        $item = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        $statusTab.IsVisible = $Directory -is [GPOToolsLdapDirectory] -and [object]::ReferenceEquals($item, $Directory.Domain)
        if (-not $statusTab.IsVisible) {
            if ($directoryTabs.SelectedItem -eq $statusTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        $role = if (-not $Directory.PdcEmulator) { '' } elseif ($Directory.IsPdcEmulator()) { Get-PSGPOText ', PDC emulator' } else { Get-PSGPOText ', not the PDC emulator ({0})' $Directory.PdcEmulator }
        $statusBaselineTextBlock.Text = Get-PSGPOText 'Baseline domain controller: {0}{1}' $Directory.Server $role
        # Collected on another domain controller (Change Domain Controller...): read again.
        $data = $healthStatus.Data
        if ($data -and -not [string]::Equals($data.Baseline, $Directory.Server, [System.StringComparison]::OrdinalIgnoreCase)) { $data = $null; $healthStatus.Data = $null }
        $statusDataPanel.IsVisible = $null -ne $data
        if (-not $data) {
            $statusCollectedTextBlock.Text = Get-PSGPOText 'No data collected yet: Detect Now reads the GPOs of each domain controller of the domain.'
            return
        }
        $statusCollectedTextBlock.Text = Get-PSGPOText 'Data collected on {0}' $data.Collected.ToString('g')
        $statusControllerList.ItemsSource = @(foreach ($controller in $data.Controllers) {
                $row = [AvaloniaControllerStatusRow]::new()
                $roles = @(if ($controller.IsPdcEmulator) { Get-PSGPOText 'PDC emulator' }) + @(if ($controller.IsBaseline) { Get-PSGPOText 'baseline' })
                $row.Name = if ($roles.Count) { '{0} ({1})' -f $controller.Name, ($roles -join ', ') } else { $controller.Name }
                if ($controller.Problem) {
                    $row.StateText = Get-PSGPOText 'Cannot be read: {0}' $controller.Problem
                    $row.Brush = '#D13438'
                } elseif ($controller.IsBaseline) {
                    $row.StateText = if ($controller.Differences) { Get-PSGPOText '{0} GPOs; {1} differences between its directory and its SYSVOL (below)' $controller.GpoCount $controller.Differences } else { Get-PSGPOText '{0} GPOs; its directory and its SYSVOL agree' $controller.GpoCount }
                    $row.Brush = if ($controller.Differences) { '#CA5010' } else { '#107C10' }
                } else {
                    $row.StateText = if ($controller.Differences) { Get-PSGPOText 'Replication in progress: {0} differences with the baseline (below)' $controller.Differences } else { Get-PSGPOText 'Replication in sync: {0} GPOs' $controller.GpoCount }
                    $row.Brush = if ($controller.Differences) { '#CA5010' } else { '#107C10' }
                }
                $row
            })
        $findings = @($data.Findings)
        $statusFindingsTextBlock.Text = if ($findings.Count) { Get-PSGPOText 'Problems found: {0}' $findings.Count } else { Get-PSGPOText 'No problem found: each GPO has its folder and its version in SYSVOL, and the domain controllers agree.' }
        $statusFindingList.IsVisible = $findings.Count -gt 0
        $checks = @{ Redirected = 'Redirected GPO'; Folder = 'Folder in SYSVOL'; Version = 'Versions'; Extension = 'Client-side extension'; OrphanFolder = 'Folder without a GPO'; Link = 'Link'; Replication = 'Replication'; DomainController = 'Domain controller' }
        $statusFindingList.ItemsSource = @(foreach ($finding in $findings) {
                $row = [AvaloniaHealthRow]::new()
                $row.SeverityText = Get-PSGPOText $finding.Severity
                $row.Brush = if ($finding.Severity -eq 'Error') { '#D13438' } else { '#CA5010' }
                $check = if ($checks[$finding.Check]) { Get-PSGPOText $checks[$finding.Check] } else { $finding.Check }
                $row.Title = Get-PSGPOText '{0}: {1}' $check $finding.Target
                $row.DomainController = $finding.DomainController
                $row.Detail = $finding.Detail
                $row
            })
    }

    function Invoke-StatusDetection {
        if ($healthStatus.Running -or $Directory -isnot [GPOToolsLdapDirectory]) { return }
        $healthStatus.Running = $true
        $statusDetectButton.IsEnabled = $false
        $statusResultTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty)
        $statusResultTextBlock.Text = Get-PSGPOText 'Reading the GPOs of each domain controller of {0}...' $Directory.DomainName
        # In the background: it reads every domain controller.
        $started = Start-ConsoleOperation -Text $statusResultTextBlock.Text -ScriptBlock { param($Directory) Get-PSGPOHealthData -Directory $Directory } -ArgumentList $Directory -Done {
            param($Result)
            $healthStatus.Data = $Result[0]
            $statusResultTextBlock.Text = ''
            Complete-StatusDetection
        } -Failed {
            param($ErrorRecord)
            $statusResultTextBlock.Text = Get-PSGPOText 'The status of the domain is not read: {0}' $ErrorRecord.Exception.GetBaseException().Message
            $statusResultTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
            Write-PSGPOLogEntry -Level Error -Source 'GPO console' -Message $statusResultTextBlock.Text -ErrorRecord $ErrorRecord
            Complete-StatusDetection
        } -Cancelled {
            $statusResultTextBlock.Text = Get-PSGPOText 'The status of the domain is not read: cancelled.'
            Complete-StatusDetection
        }
        if (-not $started) { Complete-StatusDetection }
    }

    function Complete-StatusDetection {
        $healthStatus.Running = $false
        $statusDetectButton.IsEnabled = $true
        Update-StatusTab
    }
    $statusDetectButton.Add_Click({ Invoke-StatusDetection })
}
