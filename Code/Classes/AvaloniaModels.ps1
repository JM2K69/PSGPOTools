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
    # A registry value no policy of the loaded ADMX explains, or a setting the console does not interpret
    [bool]$IsExtra
    # What tells it apart when two reports are compared (Compare-PSGPOSettingReport); empty: its
    # path and name
    [string]$Key
}

# One item of the status bar of the window: an icon (path data), a text and its tooltip
class AvaloniaStatusItem {
    [string]$IconData
    [string]$Text
    [string]$ToolTip
    # A coloured dot after the text (the version of HGPM: up to date, update available, not checked)
    [bool]$HasBadge
    [string]$BadgeBrush = '#8A8886'
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
    # 'Set for the domain' or 'Default'
    [string]$Source
    [string]$SourceBrush
    [object]$Setting
}

# One account of the permissions of a GPO (Delegation tab, Get-PSGPOPermissionFromDescriptor)
class AvaloniaPermissionRow {
    [string]$Name
    [string]$Sid
    # GpoRead, GpoApply, GpoEdit, GpoEditDeleteModifySecurity or GpoCustom
    [string]$Permission
    # As GPMC shows it, in the language of the interface
    [string]$PermissionText
    # Reads and applies the GPO (security filtering), whatever its level
    [bool]$Applies
    [bool]$Inherited
    [string]$InheritedText
}

# One PSO of the list of Show-PSOManagerAvalonia (Password Settings view)
class AvaloniaPasswordPolicyRow {
    [string]$Precedence
    [string]$Name
    [string]$Description
    # Settings in short: length, history, maximum age, lockout
    [string]$Summary
    # Number of users and groups it directly applies to
    [string]$AppliesTo
    [bool]$IsProtected
    # The PSO (GPOToolsPasswordPolicy)
    [object]$Policy
}

# One user or group: a subject of a PSO, a result of a search (Show-PSOManagerAvalonia)
class AvaloniaPasswordAccountRow {
    [string]$Name
    # User, or the scope and kind of a group, in the language of the interface
    [string]$Kind
    [string]$IconData
    [string]$DistinguishedName
    # The account (GPOToolsPasswordAccount); $null for a subject the domain does not have anymore
    [object]$Account
}

# One PSO that concerns an account, in the order of priority (Resultant Password Settings view)
class AvaloniaPasswordCandidateRow {
    [string]$Order
    [string]$Name
    [string]$Precedence
    # Directly, through which groups
    [string]$Through
    [string]$Status
    [string]$StatusBrush
    [string]$Reason
    [bool]$IsApplied
}

# One rule set of the Policy Analyzer view: a .PolicyRules file of its folder, GPOs of the domain,
# GPMC backups
class AvaloniaPolicyRuleSetItem {
    [bool]$IsChecked
    [string]$Name
    # Where it comes from and how many settings, in the language of the interface
    [string]$Detail
    [string]$Path
    # File, Domain or Gpmc
    [string]$Kind
    # The set (GPOToolsPolicyRuleSet)
    [object]$RuleSet
}

# One setting of the comparison of the Policy Analyzer view: a value and a background per set
class AvaloniaPolicyRuleRow {
    [string]$Scope
    [string]$Path
    [string]$Name
    [string]$Option
    [string[]]$Values
    [string[]]$Brushes
    # The row of Compare-PSGPOPolicyRuleSet (PSGPOTools.PolicyRuleComparison)
    [object]$Source
    # What the search reads: the texts of the row and the names of its GPOs
    [string]$SearchText
}

# One ready-made query of the WMI filter creator, its texts in the language of the interface
class AvaloniaWmiTemplateItem {
    [string]$Name
    [string]$Category
    [string]$Description
    # The query of Resources/WmiFilters.json
    [object]$Template
}

# One query of the WMI filter of the WMI filter creator, and what its check says
class AvaloniaWmiQueryRow {
    [string]$Namespace
    [string]$Query
    [string]$Status
    [string]$StatusBrush = '#107C10'
}

# The result of one query of the test of the WMI filter creator
class AvaloniaWmiTestRow {
    [string]$ResultText
    [string]$ResultBrush
    [string]$Query
    [string]$Error
}

# One change of the audit log window, its texts in the language of the interface
class AvaloniaAuditRow {
    # Local time, yyyy-MM-dd HH:mm:ss: sorted as text
    [string]$Time
    [string]$Account
    [string]$Action
    # The GPO when there is one, else the target (a container, the configuration...)
    [string]$Object
    [string]$Computer
    [string]$Domain
    # Tier0, Tier1, Tier2, Unassigned in the central log; empty in the folder of an account
    [string]$Tier
    # What the check of the entry found (Verified, Altered...), as the window shows it
    [string]$Check
    # The entry of Get-PSGPOAuditLog (PSGPOTools.AuditEntry)
    [object]$Entry
    # What the search reads, in lower case
    [string]$SearchText
}

# The value of a setting in one set, in the details of the Policy Analyzer view
class AvaloniaPolicyRuleValueItem {
    [string]$Set
    # The value each GPO of the set gives it, one per line
    [string]$Text
}
