function Get-DSCMissingPartialConfigName {
    [cmdletbinding()]
    param(
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $Message
    )

    process {
        if ($Message -imatch 'please configure .+ partial configuration blocks .+:- ?([\w, ]+).') {
            $PSCmdlet.WriteObject($Matches[1].split(",").trim())
        }
    }
}

function Set-DSCPartialConfiguration {
    [cmdletbinding()]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [string[]]
        $ConfigNames,

        [parameter()]
        [switch]
        $RestartWMI
    )

    begin {
        $path = "C:\windows\system32\configuration\MetaConfig.mof"
        $content = get-content $path -Encoding Unicode -raw

        if ($content -imatch '(instance of MSFT_PartialConfiguration(.|\n)+\n?)instance of MSFT_DSCMetaConfiguration') {
            $content = set-content $path ($content.replace($matches[1], "")) -Encoding Unicode -PassThru
        }

        $Aliases = @()

        ($content -match '\$Alias\d+$').foreach( {
                if ($_ -match '(\d+)$') {
                    $Aliases += $matches[1]
                }
            })

        $nextID = [int32]($Aliases | sort | select -Last 1) + 1

        if (($content -join '\n') -imatch '"(\[ConfigurationRepositoryWeb\].+)";') {
            $WebManager = $matches[1]
        }
    }

    process {
        $PartialAliases = @()

        $ConfigNames.foreach( {
                $partial = @"
instance of MSFT_PartialConfiguration as {0}
{
    ResourceId = "[PartialConfiguration]{1}";
    SourceInfo = "::40::9::PartialConfiguration";
    ConfigurationSource = {"{2}"};
    RefreshMode = "Pull";
};
"@
                $Id = $nextID++
                $PartialAliases += $Alias = '$Alias{0}' -f ($ID).tostring("00000000")
                $partial = $partial.Replace("{0}", $Alias).Replace("{1}", $_).Replace("{2}", $WebManager)

                $content = set-content $path ($content.replace("instance of MSFT_DSCMetaConfiguration", $partial + "instance of MSFT_DSCMetaConfiguration")) -Encoding Unicode -PassThru
            })

        $PartialConfig = "PartialConfigurations = {$($PartialAliases -join ', ')};"

        if (($content -join '\n') -imatch '(ReportManagers = {};)\n +(PartialConfigurations ?= ?.+)?') {
            if ($matches.keys.count -eq 3) {
                $content = set-content $path ($content.replace($matches[2], $PartialConfig)) -Encoding Unicode -PassThru
            }
            else {
                $content = set-content $path ($content.replace($matches[1], "$($matches[1])$PartialConfig")) -Encoding Unicode -PassThru
            }

        }
    }

    end {
        if ($RestartWMI -eq $true) {
            Restart-Service winmgmt -Force -Verbose:$false
        }
    }
}

<#

Example to auto add missing Partial Configurations

Try {
    Update-DSCConfiguration -ErrorAction Stop
} Catch {
    $_.Exception | Get-DSCMissingPartialConfigName | Set-DSCPartialConfiguration -RestartWMI
}
#>