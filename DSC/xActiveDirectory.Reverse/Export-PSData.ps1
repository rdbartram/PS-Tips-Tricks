function Export-PSData {
    [OutputType([IO.FileInfo])]

    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]
        $InputObject,

        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $DataFile
    )
    begin {
        $AllObjects = New-Object Collections.ArrayList
    }

    process {
        $null = $AllObjects.AddRange($InputObject)
    }

    end {
        $text = $AllObjects |
            Write-PowerShellHashtable -Sort
        $text |
            Set-Content -Path $DataFile -Encoding Default
        Get-Item -Path $DataFile
    }
}

function Write-PowerShellHashtable {
    [OutputType([string], [ScriptBlock])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [PSObject]
        $InputObject,

        [Alias('ScriptBlock')]
        [switch]$AsScriptBlock,

        [Switch]$Sort
    )

    process {
        $callstack = @(foreach ($_ in (Get-PSCallStack)) {
                if ($_.Command -eq "Write-PowerShellHashtable") {
                    $_
                }
            })
        $depth = $callStack.Count
        if ($inputObject -isnot [Hashtable]) {

            $newInputObject = @{
                PSTypeName = @($inputobject.pstypenames)[-1]
            }
            foreach ($prop in $inputObject.psobject.properties) {
                $newInputObject[$prop.Name] = $prop.Value
            }
            $inputObject = $newInputObject
        }

        if ($inputObject -is [Hashtable]) {
            $scriptString = ""
            $indent = $depth++ * 4
            $scriptString += " " * $indent
            $scriptString += "@{
"
            $indent = $depth * 4
            $items = $inputObject.GetEnumerator()

            if ($Sort) {
                $items = $items | Sort-Object Key
            }


            foreach ($kv in $items) {
                $scriptString += " " * $indent

                $keyString = "$($kv.Key)"
                if ($keyString.IndexOfAny(" _.#-+:;()'!?^@#$%&".ToCharArray()) -ne -1) {
                    if ($keyString.IndexOf("'") -ne -1) {
                        $scriptString += "'$($keyString.Replace("'","''"))' = "
                    } else {
                        $scriptString += "'$keyString' = "
                    }
                } elseif ($keyString) {
                    $scriptString += "$keyString = "
                }



                $value = $kv.Value
                # Write-Verbose "$value"
                if ($value -is [string]) {
                    $value = "'" + $value.Replace("'", "''").Replace("’", "’’").Replace("‘", "‘‘") + "'"
                } elseif ($value -is [ScriptBlock]) {
                    $value = "{$value}"
                } elseif ($value -is [switch]) {
                    $value = if ($value) { '$true'} else { '$false' }
                } elseif ($value -is [DateTime]) {
                    $value = if ($value) { "[DateTime]'$($value.ToString("o"))'" }
                } elseif ($value -is [bool]) {
                    $value = if ($value) { '$true'} else { '$false' }
                } elseif ($value -is [pscredential]) {
                    $value = if ($value) { "New-Object PSCredential -ArgumentList ('$($value.username)', (ConvertTo-SecureString '$($Value.GetNetworkCredential().Password)' -AsPlainText -Force))"}
                } elseif ($value -and $value.GetType -and ($value.GetType().IsArray -or $value -is [Collections.IList])) {
                    $value = foreach ($v in $value) {
                        if ($v -is [Hashtable]) {
                            Write-PowerShellHashtable $v -Sort
                        } elseif ($v -is [Object] -and $v -isnot [string]) {
                            Write-PowerShellHashtable $v -Sort
                        } else {
                            ("'" + "$v".Replace("'", "''").Replace("’", "’’").Replace("‘", "‘‘") + "'")
                        }
                    }
                    $oldOfs = $ofs
                    $ofs = ",
$(' ' * ($indent + 4))"
                    $value = @"
@(
$value
)
"@
                    $ofs = $oldOfs
                } elseif ($value -as [Hashtable[]]) {
                    $value = foreach ($v in $value) {
                        Write-PowerShellHashtable $v -Sort
                    }
                    $value = @"
@(
$($value -join ",")
)
"@
                } elseif ($value -is [Hashtable]) {
                    $value = "$(Write-PowerShellHashtable $value -Sort)"
                } elseif ($value -as [Double]) {
                    $value = "$value"
                } else {
                    $valueString = "'$value'"
                    if ($valueString[0] -eq "'" -and
                        $valueString[1] -eq "@" -and
                        $valueString[2] -eq "{") {
                        $value = Write-PowerShellHashtable -InputObject $value -Sort
                    } else {
                        $value = $valueString
                    }

                }
                $scriptString += "$value
"
            }
            $scriptString += " " * ($depth - 1) * 4
            $scriptString += "}"
            if ($AsScriptBlock) {
                [ScriptBlock]::Create($scriptString)
            } else {
                $scriptString
            }
            #endregion Include
        }
    }
}
