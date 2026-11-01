<#
    Starter GPOs, as GPMC shows them under the domain: read when their node is selected the first
    time (their folder of SYSVOL, in the background), and again after a change; New Starter GPO...
    (empty, or with the Administrative Templates of a GPO), New GPO from Starter GPO... (the New GPO
    form, started from it) and Delete Starter GPO... (a Custom one).

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerStarterGpoView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerStarterGpoView {
    # List: the Starter GPOs read ($null: not read yet); Problem: why they cannot be read;
    # SelectId: the Starter GPO to select once read again; Result: what a change did, said then;
    # Gpos: the GPOs of the form, by index; Delete: the Starter GPO of the deletion form.
    $starterGpos = @{ List = $null; Problem = $null; Loading = $false; SelectId = $null; Result = $null; ResultProblem = $false; Gpos = @(); Delete = $null }

    # Reads the Starter GPOs in the background, then the tree again: the Starter GPO of SelectId
    # selected, else the Starter GPOs node; what a change did said under the details.
    function Update-StarterGpoList {
        if ($starterGpos.Loading -or -not $Directory) { return }
        $starterGpos.Loading = $true
        $started = Start-ConsoleOperation -Text (Get-PSGPOText 'Reading the Starter GPOs of {0}...' $Directory.DomainName) -ScriptBlock {
            param($Directory)
            Get-PSGPOStarterGpoData -Directory $Directory
        } -ArgumentList $Directory -Done {
            param($Result)
            $starterGpos.Loading = $false
            $starterGpos.List = @(foreach ($item in $Result) { if ($item) { $item } })
            $starterGpos.Problem = $null
            Show-StarterGpoList
        } -Failed {
            param($ErrorRecord)
            $starterGpos.Loading = $false
            $starterGpos.List = @()
            $starterGpos.Problem = $ErrorRecord.Exception.GetBaseException().Message
            Show-StarterGpoList
        } -Cancelled {
            $starterGpos.Loading = $false
        }
        if (-not $started) { $starterGpos.Loading = $false }
    }

    # The tree with the Starter GPOs read, and what a change did.
    function Show-StarterGpoList {
        $select = @($starterGpos.List | Where-Object { $null -ne $starterGpos.SelectId -and $_.Id -eq $starterGpos.SelectId })[0]
        Update-DirectoryTree -Select $(if ($select) { $select } else { 'StarterGpos' })
        $starterGpos.SelectId = $null
        if ($starterGpos.Result) { Show-DirectoryResult -Text $starterGpos.Result -Problem:$starterGpos.ResultProblem }
        $starterGpos.Result = $null
        $starterGpos.ResultProblem = $false
    }

    # The selected node is the Starter GPOs or one of them, not read yet: read them.
    function Test-StarterGpoNode {
        param($Item)
        $isStarter = $Item -eq 'StarterGpos' -or ($null -ne $Item -and $Item.PSObject.TypeNames -contains 'PSGPOTools.StarterGpo')
        if ($isStarter -and $null -eq $starterGpos.List) { Update-StarterGpoList }
    }

    function Open-StarterGpoForm {
        if (-not $Directory) { return }
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $starterGpoTitleTextBlock.Text = Get-PSGPOText 'New Starter GPO in {0}: the Administrative Templates new GPOs start from' $Directory.DomainName
        $starterGpoNameTextBox.Text = ''
        $starterGpoDescriptionTextBox.Text = ''
        $starterGpos.Gpos = @($Directory.Gpos)
        $starterGpoSourceComboBox.ItemsSource = @(Get-PSGPOText 'None: an empty Starter GPO') + @(foreach ($gpo in $starterGpos.Gpos) { Get-PSGPOText 'The Administrative Templates of {0}' $gpo.DisplayName })
        $starterGpoSourceComboBox.SelectedIndex = 0
        $starterGpoErrorTextBlock.Text = ''
        Show-DirectoryForm $starterGpoPanel
        $null = $starterGpoNameTextBox.Focus()
    }

    function Submit-StarterGpo {
        $name = "$($starterGpoNameTextBox.Text)".Trim()
        if (-not $name) { $starterGpoErrorTextBlock.Text = Get-PSGPOText 'The name of the Starter GPO is required.'; return }
        if (@($starterGpos.List | Where-Object { [string]::Equals($_.DisplayName, $name, [System.StringComparison]::OrdinalIgnoreCase) }).Count) {
            $starterGpoErrorTextBlock.Text = Get-PSGPOText "A Starter GPO named '{0}' already exists in {1}." $name $Directory.DomainName
            return
        }
        $starterGpoErrorTextBlock.Text = ''
        $source = if ($starterGpoSourceComboBox.SelectedIndex -gt 0) { $starterGpos.Gpos[$starterGpoSourceComboBox.SelectedIndex - 1] }
        $null = Start-ConsoleOperation -NoCancel -Text (Get-PSGPOText "Creating the Starter GPO '{0}'..." $name) -ScriptBlock {
            param($Directory, $Name, $Description, $Source)
            $settings = @{}
            if ($Source) { $settings = Select-PSGPOStarterSettingFile -Files $Directory.ReadGpoFolder($Source) }
            $id = [guid]::NewGuid()
            $Directory.WriteStarterGpo($id, $Name, (New-PSGPOStarterGpoFile -Id $id -DisplayName $Name -Description $Description -Settings $settings))
            [pscustomobject]@{ Id = $id; Settings = $settings.Count }
        } -ArgumentList $Directory, $name, "$($starterGpoDescriptionTextBox.Text)", $source -Done {
            param($Result)
            $created = @($Result)[0]
            $starterGpoPanel.IsVisible = $false
            $starterGpos.List = $null
            $starterGpos.SelectId = $created.Id
            $starterGpos.Result = (Get-PSGPOText "Starter GPO '{0}' created." $starterGpoNameTextBox.Text.Trim()) +
                $(if ($starterGpoSourceComboBox.SelectedIndex -gt 0 -and -not $created.Settings) { ' ' + (Get-PSGPOText 'The GPO has no Administrative Template: the Starter GPO is empty.') })
            Update-StarterGpoList
        } -Failed {
            param($ErrorRecord)
            $starterGpoErrorTextBlock.Text = $ErrorRecord.Exception.GetBaseException().Message
        }
    }

    function Open-DeleteStarterGpoForm {
        $starter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($null -eq $starter -or $starter.PSObject.TypeNames -notcontains 'PSGPOTools.StarterGpo' -or $starter.Type -eq 'System') { return }
        $starterGpos.Delete = $starter
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $deleteStarterGpoTextBlock.Text = Get-PSGPOText "Delete the Starter GPO '{0}'? The GPOs created from it keep their settings: they are copies." $starter.DisplayName
        $deleteStarterGpoErrorTextBlock.Text = ''
        Show-DirectoryForm $deleteStarterGpoPanel
    }

    function Submit-DeleteStarterGpo {
        $starter = $starterGpos.Delete
        if (-not $starter) { return }
        $null = Start-ConsoleOperation -NoCancel -Text (Get-PSGPOText "Deleting the Starter GPO '{0}'..." $starter.DisplayName) -ScriptBlock {
            param($Directory, $Id, $Name)
            $Directory.RemoveStarterGpo($Id, $Name)
        } -ArgumentList $Directory, $starter.Id, $starter.DisplayName -Done {
            $deleteStarterGpoPanel.IsVisible = $false
            $starterGpos.List = $null
            $starterGpos.Result = Get-PSGPOText "Starter GPO '{0}' deleted." $starterGpos.Delete.DisplayName
            $starterGpos.Delete = $null
            Update-StarterGpoList
        } -Failed {
            param($ErrorRecord)
            $deleteStarterGpoErrorTextBlock.Text = $ErrorRecord.Exception.GetBaseException().Message
        }
    }

    $newStarterGpoMenuItem.Add_Click({ Open-StarterGpoForm })
    $newGpoFromStarterMenuItem.Add_Click({
            $starter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
            if ($null -ne $starter -and $starter.PSObject.TypeNames -contains 'PSGPOTools.StarterGpo') { Open-NewGpoForm -Som $null -StarterGpo $starter }
        })
    $deleteStarterGpoMenuItem.Add_Click({ Open-DeleteStarterGpoForm })
    $starterGpoCreateButton.Add_Click({ Submit-StarterGpo })
    $starterGpoCancelButton.Add_Click({ $starterGpoPanel.IsVisible = $false })
    $starterGpoNameTextBox.Add_KeyDown({
            param($control, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-StarterGpo; $e.Handled = $true }
            elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $starterGpoPanel.IsVisible = $false; $e.Handled = $true }
        })
    $deleteStarterGpoConfirmButton.Add_Click({ Submit-DeleteStarterGpo })
    $deleteStarterGpoCancelButton.Add_Click({ $deleteStarterGpoPanel.IsVisible = $false })
}
