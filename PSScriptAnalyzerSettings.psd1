# Rules of PSScriptAnalyzer for the sources (Code/), run by the CI:
#   Invoke-ScriptAnalyzer -Path ./Code -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The private functions that write are called by the public commands, which support
        # -WhatIf and -Confirm (a test checks it): a second confirmation would ask twice.
        'PSUseShouldProcessForStateChangingFunctions'
        # False positives: a parameter used inside a script block (a closure, an LDAP change), and
        # the sender of an Avalonia event handler, which the signature needs but few handlers use.
        'PSReviewUnusedParameter'
    )
}
