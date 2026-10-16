<#
    Lightweight bindable node types used by Show-GPOManagerAvalonia.

    These are defined as real PowerShell classes (not PSCustomObject) so that Avalonia's
    reflection-based data binding (TreeDataTemplate / DataGrid columns) can see genuine
    CLR properties on them.
#>

class AvaloniaTreeNode {
    [string]$Header
    # Icon of Resources/Icons (Set-PSGPOTreeNodeIcon): its name, path data and colour
    [string]$Icon
    [string]$IconData
    [string]$IconBrush
    [System.Collections.ObjectModel.ObservableCollection[object]]$Children
    [AvaloniaTreeNode]$Parent
    [object]$Tag
    # Bound two-way to TreeViewItem.IsExpanded
    [bool]$IsExpanded

    AvaloniaTreeNode() {
        $this.Children = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    }
}

class AvaloniaRegistryRow {
    [string]$Key
    [string]$Value
}

# One registry change of the "Registry Preview" list (Show-GPOManagerAvalonia, Setting tab)
class AvaloniaPreviewRow {
    [string]$Title
    [string]$Key
    [string]$ValueName
    [string]$Data
}

# One configured setting of the Settings tab of a GPO (Get-PSGPOConfiguredSetting)
class AvaloniaSettingRow {
    # Category path ('Policies > Administrative Templates > ...'), or 'Extra Registry Settings'
    [string]$Path
    [string]$Name
    [string]$State
    # One 'Label: value' line per option
    [string]$Options
    # A registry value no policy of the loaded ADMX explains
    [bool]$IsExtra
}

# One item of the status bar of the window: an icon (path data), a text and its tooltip
class AvaloniaStatusItem {
    [string]$IconData
    [string]$Text
    [string]$ToolTip
}

# One GPO link of the Group Policy Management details ("Linked Group Policy Objects", "Links")
class AvaloniaLinkRow {
    [int]$Order
    [string]$Name
    [string]$Location
    [string]$Enforced
    [string]$LinkEnabled
    [string]$Status
}

# One node of the timeline of a GPO (History tab): a backup, or the GPO as it is now
class AvaloniaHistoryNode {
    [string]$Title
    [string]$Subtitle
    # What changed from the previous node: "+2 ~1 -0", or "first backup"
    [string]$Summary
    [string]$NodeFill
    [string]$NodeStroke
    [string]$LineBrush
    # The backup (PSGPOTools.Backup); $null for the current state
    [object]$Backup
    [bool]$IsCurrent
    # The changes from the previous node (Compare-PSGPOSettingReport), and the date of that node
    [object[]]$Changes
    [string]$Previous
    # Notes of the backup: its labels on the node, its comment as its tool tip ($null: none)
    [string]$LabelsText
    [bool]$HasLabels
    [string]$LabelBrush
    [object]$Comment
    # The approved version of the GPO (Backup.ApprovedLabel of the configuration)
    [bool]$IsApproved
}

# One change of a setting between two nodes of the timeline (History tab)
class AvaloniaChangeRow {
    [string]$Change
    [string]$ChangeBrush
    [string]$Location
    [string]$Name
    [string]$Before
    [string]$After
    [bool]$HasBefore
    [bool]$HasAfter
}

# One item of a preference type in the editor (preferences panel)
class AvaloniaPreferenceRow {
    [string]$Name
    [string]$Summary
    # Disabled, targeting filters, stored password...
    [string]$Flags
    # The item (Get-PSGPOPreferenceItem)
    [object]$Item
}

# One setting of the configuration window (Get-PSGPOConfigurationSetting)
class AvaloniaConfigurationRow {
    [string]$Key
    [string]$Value
    [string]$Default
    # 'Set in your configuration' or 'Default'
    [string]$Source
    [string]$SourceBrush
    [object]$Setting
}
