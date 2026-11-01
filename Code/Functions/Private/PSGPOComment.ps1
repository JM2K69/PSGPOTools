<#
    The comment of a GPO, as GPMC keeps it: the file GPO.cmt at the root of the folder of the GPO
    in SYSVOL, in UTF-16 with a byte order mark. It is not a setting the computers apply: writing it
    does not change the version of the GPO (GPMC does not either).
#>

# The text of GPO.cmt: '' without a file. UTF-16 (little or big endian) or UTF-8 by their byte
# order mark; without one, UTF-16 when the second byte is zero (an ASCII character), else UTF-8.
function ConvertFrom-PSGPOCommentByte {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyCollection()] [byte[]]$Bytes)

    if (-not $Bytes -or -not $Bytes.Length) { return '' }
    $text = if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2) }
    elseif ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3) }
    elseif ($Bytes.Length -ge 2 -and $Bytes[1] -eq 0) { [System.Text.Encoding]::Unicode.GetString($Bytes) }
    else { [System.Text.Encoding]::UTF8.GetString($Bytes) }
    $text.TrimEnd([char]0)
}

# GPO.cmt for a comment, as GPMC writes it: UTF-16 little endian with its byte order mark; the
# line ends as CR LF.
function ConvertTo-PSGPOCommentByte {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([AllowEmptyString()] [string]$Comment)

    $text = ("$Comment" -replace '\r?\n', "`r`n")
    , [byte[]]([System.Text.Encoding]::Unicode.GetPreamble() + [System.Text.Encoding]::Unicode.GetBytes($text))
}
