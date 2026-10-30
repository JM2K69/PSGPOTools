<#
    The Group Policy Management view: the views of the console (Show-View), the editor opened on a
    GPO, the tree of the domain (its OUs, GPOs, WMI filters, deleted GPOs) built and kept expanded
    when read again.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerDirectoryView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerDirectoryView {
    function Show-View {
        param([ValidateSet('Management', 'Editor')][string]$View)
        $managementView.IsVisible = $View -eq 'Management'
        $editorView.IsVisible = $View -eq 'Editor'
        $managementButton.IsVisible = $View -eq 'Editor'
        $browseAdmxButton.IsVisible = $View -eq 'Management'
        # A domain read over LDAP is read again; a description in memory has nothing to read.
        $refreshButton.IsVisible = $View -eq 'Management' -and $Directory -is [GPOToolsLdapDirectory]
        $searchPanel.IsVisible = $View -eq 'Editor'
        $subtitleTextBlock.Text = if ($View -eq 'Management') {
            if (-not $Directory) { Get-PSGPOText 'Group Policy Management' }
            elseif ($Directory.IsDemonstration) { Get-PSGPOText 'Group Policy Management - {0} (demonstration)' $Directory.DomainName }
            elseif ($Directory -is [GPOToolsLdapDirectory]) {
                if ($Directory.Account) { Get-PSGPOText 'Group Policy Management - {0} ({1}) - connected as {2}' $Directory.DomainName $Directory.ServerType $Directory.Account }
                else { Get-PSGPOText 'Group Policy Management - {0} ({1})' $Directory.DomainName $Directory.ServerType }
            }
            elseif ($Directory.IsReadOnly) { Get-PSGPOText 'Group Policy Management - {0} (read-only)' $Directory.DomainName }
            else { Get-PSGPOText 'Group Policy Management - {0}' $Directory.DomainName }
        } elseif ($editing.Gpo) { Get-PSGPOText 'Editing the GPO {0}' $editing.Gpo.DisplayName } else { Get-PSGPOText 'Explore and manage Group Policy Objects' }
    }

    # Opens the policy editor on a GPO ($null: browse the ADMX policies, outside any GPO).
    function Open-GpoEditor {
        param([GPOToolsGpo]$Gpo)
        if (Wait-ConsoleAdmx -Then ${function:Open-GpoEditor} -ArgumentList @(, $Gpo)) { return }
        $editing.Gpo = $Gpo
        # The settings of the GPO: its Registry.pol for each scope (empty when it has none).
        $editing.Pol = @{}
        $editing.Template = $null
        $editing.Audit = $null
        $editing.Preferences = @{}
        $editing.PolError = $null
        $scripts.Lists = @{}
        if ($Gpo) {
            try {
                foreach ($scope in 'Machine', 'User') {
                    $editing.Pol[$scope] = [GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($Gpo, $scope))
                }
                # Its security settings: GptTmpl.inf, a new empty template when the GPO has none.
                $editing.Template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo))
                # Its advanced audit policy: audit.csv, empty when the GPO has none.
                $editing.Audit = [GPOToolsAuditPolicyFile]::Parse($Directory.ReadAuditPolicyFile($Gpo))
            } catch {
                $editing.PolError = Get-PSGPOText 'The settings of the GPO cannot be read: {0}' $_.Exception.GetBaseException().Message
                $editing.Pol = @{}
                $editing.Template = $null
                $editing.Audit = $null
            }
        }
        $treeView.SelectedItem = $null
        # The filter on the configured settings only applies to a GPO; rebuilt for this one.
        $configuredOnlyCheckBox.IsVisible = $null -ne $Gpo
        if (-not $Gpo -and $configuredOnlyCheckBox.IsChecked) { $configuredOnlyCheckBox.IsChecked = $false }
        elseif ($configuredOnlyCheckBox.IsChecked) { Update-PolicyTree }
        $editingBanner.IsVisible = $null -ne $Gpo
        $editingGpoTextBlock.Text = if (-not $Gpo) { '' }
            elseif ($editing.PolError) { Get-PSGPOText "Editing the GPO '{0}' [{1}]: {2}" $Gpo.DisplayName $Directory.DomainName $editing.PolError }
            else { Get-PSGPOText "Editing the GPO '{0}' [{1}]" $Gpo.DisplayName $Directory.DomainName }
        # Its status may disable a part: it can be edited, as in GPMC, but does not apply.
        $editingStatusTextBlock.Text = if ($Gpo) {
            switch ($Gpo.Flags -band 3) {
                1 { Get-PSGPOText 'The GPO status disables its User Configuration: its settings are saved, but the users do not apply them.' }
                2 { Get-PSGPOText 'The GPO status disables its Computer Configuration: its settings are saved, but the computers do not apply them.' }
                3 { Get-PSGPOText 'The GPO status disables all its settings: they are saved, but nobody applies them.' }
            }
        }
        Update-ApplyButton
        Show-View 'Editor'
    }

    # Keys of the expanded nodes, to keep them expanded when the tree is rebuilt.
    function Get-ExpandedKey {
        $keys = [System.Collections.Generic.HashSet[string]]::new()
        $stack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($root in @($domainTreeView.ItemsSource)) { if ($root) { $stack.Push($root) } }
        while ($stack.Count) {
            $node = $stack.Pop()
            if ($node.IsExpanded) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $node)") }
            foreach ($child in $node.Children) { $stack.Push($child) }
        }
        , $keys
    }

    # The recycle bin and the templates: from the backups of the folder of the History tab, read
    # again when that folder changes or with -Force (after a deletion, a restore, new notes).
    $backupLists = @{ Root = $null; Deleted = @(); Templates = @(); RootProblem = $null }
    function Update-BackupList {
        param([switch]$Force)
        # Central backups, for Tier 0 only: no Deleted GPOs for the others, nor where the share is
        # not reached (not mounted on Linux).
        if (-not (Test-PSGPOBackupAllowed -Directory $Directory)) {
            $backupLists.Deleted = $null
            $backupLists.Templates = @()
            return
        }
        $root = Get-HistoryRoot
        if (-not $Force -and $backupLists.Root -eq $root) { return }
        $backupLists.Root = $root
        if (-not $root) {
            $backupLists.Deleted = $null
            $backupLists.Templates = @()
            return
        }
        try {
            $backupLists.Deleted = @(Get-PSGPODeletedGpoBackup -Directory $Directory -Path $root)
            $backupLists.Templates = @(Get-PSGPOTemplateBackup -Path $root)
        } catch {
            $backupLists.Deleted = @()
            $backupLists.Templates = @()
        }
    }

    # Rebuilds the tree and selects the first node whose Tag is $Select, its parents expanded.
    function Update-DirectoryTree {
        param($Select)
        Update-BackupList
        $keys = Get-ExpandedKey
        if ($null -ne $Select) {
            $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys -DeletedGpo $backupLists.Deleted
            $target = $null
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count -and -not $target) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select) -or ($Select -is [string] -and $node.Tag -is [string] -and $node.Tag -eq $Select)) { $target = $node }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
            for ($parent = $target.Parent; $parent; $parent = $parent.Parent) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $parent)") }
        }
        $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys -DeletedGpo $backupLists.Deleted
        $domainTreeView.ItemsSource = $roots
        if ($null -ne $Select) {
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select) -or ($Select -is [string] -and $node.Tag -is [string] -and $node.Tag -eq $Select)) { $domainTreeView.SelectedItem = $node; break }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
        }
    }
}
