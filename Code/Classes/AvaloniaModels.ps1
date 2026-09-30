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

    AvaloniaTreeNode() {
        $this.Children = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    }
}

class AvaloniaRegistryRow {
    [string]$Key
    [string]$Value
}
