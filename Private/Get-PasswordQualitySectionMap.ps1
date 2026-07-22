function Get-PasswordQualitySectionMap {
    <#
    .SYNOPSIS
        Maps the section headings emitted by DSInternals' Test-PasswordQuality to stable keys.

    .DESCRIPTION
        Test-PasswordQuality renders its result as an English text report whose headings are
        full sentences. Those sentences are unstable identifiers: they are long, they read
        badly as property names, and they have changed wording between DSInternals releases.

        This map translates them to short keys that the rest of the module keys off, so a
        future wording change is a one-line fix here rather than a rewrite of every caller.

        Severity is this module's own opinion, not something DSInternals reports. It exists
        to let reports sort findings by how much they should worry you.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $map = [ordered]@{
        'Passwords of these accounts are stored using reversible encryption:'         = @{ Key = 'ReversibleEncryption';     Severity = 'High';     Layout = 'Flat' }
        'LM hashes of passwords of these accounts are present:'                       = @{ Key = 'LMHash';                   Severity = 'High';     Layout = 'Flat' }
        'These accounts have no password set:'                                        = @{ Key = 'NoPasswordSet';            Severity = 'Critical'; Layout = 'Flat' }
        'Passwords of these accounts have been found in the dictionary:'              = @{ Key = 'InDictionary';             Severity = 'Critical'; Layout = 'Flat' }
        'These groups of accounts have the same passwords:'                           = @{ Key = 'DuplicatePasswords';       Severity = 'High';     Layout = 'Grouped' }
        'These user accounts have the SamAccountName as password:'                    = @{ Key = 'SamAccountNameAsPassword'; Severity = 'Critical'; Layout = 'Flat' }
        'These computer accounts have default passwords:'                             = @{ Key = 'DefaultComputerPassword';  Severity = 'High';     Layout = 'Flat' }
        'Kerberos AES keys are missing from these accounts:'                          = @{ Key = 'MissingAESKeys';           Severity = 'Medium';   Layout = 'Flat' }
        'Kerberos pre-authentication is not required for these accounts:'             = @{ Key = 'PreAuthNotRequired';       Severity = 'High';     Layout = 'Flat' }
        'Only DES encryption is allowed to be used with these accounts:'              = @{ Key = 'DESOnly';                  Severity = 'High';     Layout = 'Flat' }
        'These accounts are susceptible to the Kerberoasting attack:'                 = @{ Key = 'Kerberoastable';           Severity = 'High';     Layout = 'Flat' }
        'These administrative accounts are allowed to be delegated to a service:'     = @{ Key = 'DelegatableAdmin';         Severity = 'High';     Layout = 'Flat' }
        'Passwords of these accounts will never expire:'                              = @{ Key = 'PasswordNeverExpires';     Severity = 'Low';      Layout = 'Flat' }
        'These accounts are not required to have a password:'                         = @{ Key = 'PasswordNotRequired';      Severity = 'High';     Layout = 'Flat' }
        'These accounts that require smart card authentication have a password:'      = @{ Key = 'SmartCardWithPassword';    Severity = 'Medium';   Layout = 'Flat' }
    }

    return $map
}
