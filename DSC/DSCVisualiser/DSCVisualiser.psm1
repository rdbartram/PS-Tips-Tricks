function Get-MOFFile {
    [CmdletBinding()]
    param
    (
        [string]$Path
    )

    Begin {
        $MofFile = Get-Content $Path -Encoding Unicode
        $Counter = 0
        $Instances = @()
        foreach ($line in $MofFile) {
            $Trimmed = $line.Trim();
            if ($Trimmed.StartsWith('instance of')) {
                $Instances += $Counter
            }
            $Counter ++
        }
    }
    Process {
        $Finish = $Instances.Count
        For ($Counter = 0; $Counter -lt $Finish; $Counter++) {
            $Start = $Instances[$Counter]
            $End = $Instances[$Counter + 1]
            if ($End -eq $null) {
                $End = $MofFile.Count
            }
            $Instance = $MofFile[$Start..($End - 1)]
            $InstanceName = $Instance[0] -replace (' *instance of ([0-9a-z_]+) *.*', '$1')
            Write-Verbose $InstanceName
            try {
                @{
                    Type = $Type
                    Data = $Instance
                }
            } catch {
            }
        }
    }
    End {

    }
}

function ConvertTo-MOFInstance {
    [CmdletBinding()]
    param
    (
        [string[]]
        $MofData
    )

    process {
        $ReturnObject = @{}

        if ($MofData[0] -match 'Instance of (.+) as (.+)') {
            $ReturnObject.add("MOFInstanceID", $Matches[2])
            $ReturnObject.add("MOFInstanceType", $Matches[1])
        }

        $MofData | % {
            if ($_ -match '([^ ]+) *= *"?([^"]+)"?;$') {
                $ReturnObject.Add($matches[1], $matches[2])
            }

            if ($_ -match '([^ ]+) *= {') {
                $Data = @()
                $Property = $Matches[1]
            }

            if ($Property -and $data) {
                if ($_ -match '"(.+)"') {
                    $Data += $matches[1]
                }
            }

            if ($_ -match '"(.+)"};') {
                $Data += $Matches[1]
                $ReturnObject.Add($Property, $Data)
                $Property = $null
                $Data = $null
            }

            if ($_ -match 'OMI_ConfigurationDocument') {
                $ReturnObject.Add("MOFInstanceType", $matches[0])
            }
        }

        [PSCustomObject]$ReturnObject
    }
}

function Read-DSCMOFConfiguration {
    [cmdletbinding()]
    param (
        $Path
    )

    (Get-MOFFile -Path $Path) | % { ConvertTo-MOFInstance -MofData $_.Data }
}

function New-DSCVisualisation {

    [cmdletbinding()]
    param(
        [parameter()]
        [Object[]]
        $Config
    )

    $Resources = $Config.where{$_.mofinstancetype -ne "OMI_ConfigurationDocument"}

    graph DSC {
        $Composites = @()
        node -Default @{shape = 'box'}
        $Resources.where( {$_.dependson -eq $null -and $_.MOFInstanceType -ne "MSFT_Credential"}).foreach( {
                $obj = $_ | Select -Property * -ExcludeProperty SourceInfo, ModuleName, ModuleVersion, MOFInstanceID, MOFInstanceType, ResourceId
                if ($_.resourceid -match '(.+)::(.+)') {
                    $Composites += [pscustomobject]@{ConfigurationName = $_.ConfigurationName; Name = $Matches[2]}
                    entity $Obj -Name $matches[1] -Show Value
                    edge $matches[2] -To $matches[1]
                } else {
                    write-verbose "creating entity with name $($_.resourceid)"
                    entity $Obj -Name $_.ResourceId.tolower() -Show Value
                    edge $_.ConfigurationName.tolower() -To $_.ResourceId.tolower()
                }
            })

        $Resources.where( {$_.dependsOn}).foreach( {
                $obj = $_ | Select -Property * -ExcludeProperty SourceInfo, ModuleName, ModuleVersion, MOFInstanceID, MOFInstanceType, ResourceId
                if ($_.ResourceId -match '(.+)::(.+)') {
                    $Child = $matches[1]
                } else {
                    $Child = $_.ResourceId
                }
                $_.dependson.foreach( {
                        entity $Obj -Name $Child.tolower() -Show Value
                        if ($_ -match '(.+)::(.+)') {
                            edge $matches[1].tolower() -To $Child.tolower()
                        } else {
                            edge $_.tolower() -To $Child.tolower()
                        }
                    })
            })

        $Composites | select -Unique Name, configurationname| % {
            edge $_.ConfigurationName.tolower() -To $_.Name.tolower()
        }
    } | Export-PSGraph -ShowGraph -OutputFormat png

}

Export-ModuleMember Read-DSCMOFConfiguration, New-DSCVisualisation
