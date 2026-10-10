<#
    Lightweight bindable node types used by Show-GPOManagerAvalonia.

    These are defined as real PowerShell classes (not PSCustomObject) so that Avalonia's
    reflection-based data binding (TreeDataTemplate / DataGrid columns) can see genuine
    CLR properties on them.
#>

class AvaloniaTreeNode {
    [string]$Header
    [string]$Icon
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

# One GPO link of the Group Policy Management details ("Linked Group Policy Objects", "Links")
class AvaloniaLinkRow {
    [int]$Order
    [string]$Name
    [string]$Location
    [string]$Enforced
    [string]$LinkEnabled
    [string]$Status
}
