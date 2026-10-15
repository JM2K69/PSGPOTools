<#
    Group Policy Preferences ([MS-GPPREF]): one XML file per preference type in the folder of a
    GPO, <Machine|User>\Preferences\<type>\<type>.xml. An outer element (with the clsid of the
    type) holds the items (inner elements, with their own clsid), each with its Properties
    element; Registry items can be grouped in Collection elements.

    GPOToolsPreferenceFile keeps the XML document as read: the attributes and elements the
    console does not edit (item-level targeting, the elements of the types it does not edit)
    are written back as they are.
#>

class GPOToolsPreferenceFile {
    [System.Xml.XmlDocument]$Document
    # The file had a UTF-8 byte order mark: written back with it.
    hidden [bool]$Bom

    static [GPOToolsPreferenceFile] Parse([byte[]]$Bytes) {
        $File = [GPOToolsPreferenceFile]::new()
        $File.Bom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
        $File.Document = [System.Xml.XmlDocument]::new()
        $File.Document.PreserveWhitespace = $false
        # Not resolved: a preference file has no DTD.
        $File.Document.XmlResolver = $null
        $Stream = [System.IO.MemoryStream]::new($Bytes)
        try { $File.Document.Load($Stream) } finally { $Stream.Dispose() }
        return $File
    }

    # An empty file of a preference type: its outer element only.
    static [GPOToolsPreferenceFile] Create([string]$Root, [string]$RootClsid) {
        $File = [GPOToolsPreferenceFile]::new()
        $File.Document = [System.Xml.XmlDocument]::new()
        [void]$File.Document.AppendChild($File.Document.CreateXmlDeclaration('1.0', 'utf-8', $null))
        $Element = $File.Document.CreateElement($Root)
        $Element.SetAttribute('clsid', $RootClsid)
        [void]$File.Document.AppendChild($Element)
        return $File
    }

    [System.Xml.XmlElement] GetRoot() { return $this.Document.DocumentElement }

    # UTF-8 with the XML declaration, one item per line, as GPMC writes them.
    [byte[]] ToBytes() {
        $Settings = [System.Xml.XmlWriterSettings]::new()
        $Settings.Encoding = [System.Text.UTF8Encoding]::new($this.Bom)
        $Settings.Indent = $true
        $Settings.IndentChars = "`t"
        $Settings.NewLineChars = "`r`n"
        $Stream = [System.IO.MemoryStream]::new()
        $Writer = [System.Xml.XmlWriter]::Create($Stream, $Settings)
        try {
            $this.Document.Save($Writer)
        } finally {
            $Writer.Dispose()
        }
        return $Stream.ToArray()
    }
}

# A preference type of a scope in the tree of the policy editor (Tag of its node).
class GPOToolsPreferenceNode {
    # Machine or User
    [string]$Scope
    # The type in the catalog (Get-PSGPOPreferenceExtension)
    [object]$Extension

    GPOToolsPreferenceNode([string]$Scope, [object]$Extension) {
        $this.Scope = $Scope
        $this.Extension = $Extension
    }

    [string] ToString() { return "$($this.Extension.Name) ($($this.Scope))" }
}
