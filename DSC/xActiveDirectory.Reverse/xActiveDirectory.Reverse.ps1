<#PSScriptInfo

.VERSION 1.0.0.2

.GUID 0d8b95b1-ed9a-4d37-b4c2-4a00575b62f5

.AUTHOR Ryan Bartram

.COMPANYNAME DFTAI (Don't Forget To Automate It)

.EXTERNALMODULEDEPENDENCIES

.TAGS Windows,ReverseDSC,xActiveDirectory,AD,ActiveDirectory

.RELEASENOTES

* Added support for Organizational Units;
#>

#Requires -Modules @{ModuleName="ReverseDSC";ModuleVersion="1.9.2.5";}, @{ModuleName="xActiveDirectory";ModuleVersion="2.17.0.0";}

<#

.DESCRIPTION
 Extracts the DSC Configuration of an existing environment, allowing you to analyze it or to replicate it.

#>

param(
    [parameter(Mandatory)]
    [System.String[]]
    $BaseSearch,

    [parameter()]
    [string]
    $OutputPath
)

<## Script Settings #>
$VerbosePreference = "SilentlyContinue"

<## Scripts Variables #>
$Script:DSCPath = (Get-Module xActiveDirectory -ListAvailable).ModuleBase
$Script:configName = "ADConfiguration"

$Script:DSCModulesImports = @(
    @{
        Name    = "xActiveDirectory"
        Version = "2.17.0.0"
    }
)

function Orchestrator {
    param (
        [parameter(Mandatory)]
        [System.String[]]
        $BaseSearch
    )

    Import-ReverseDSC

    Write-Information "Configuring Dependencies..."
    $DSCDependentModules = Get-DSCDependentModules

    Write-Information "Scanning [OUs]..."
    $OUs = Read-OUs -BaseSearch $BaseSearch

    Write-Information "Generating OU Configuration Script block..."
    $OUDSCConfig = New-OUDSCConfig

    Write-Information "Configuring Local Configuration Manager (LCM)..."
    $LCMConfig = New-LCMConfig

    $ConfigurationScript = @(New-ConfigurationScriptComments)
    $ConfigurationScript += ""
    $ConfigurationScript += "Configuration $Script:configName {"
    $ConfigurationScript += "param ("
    $ConfigurationScript += "    [PSCredential]"
    $ConfigurationScript += "    `$DomainCredential"
    $ConfigurationScript += ")"
    $ConfigurationScript += ""
    $ConfigurationScript += $DSCDependentModules
    $ConfigurationScript += ""
    $ConfigurationScript += "    Node `$AllNodes.Nodename {"
    $ConfigurationScript += ""
    $ConfigurationScript += $LCMConfig
    $ConfigurationScript += ""
    $ConfigurationScript += $OUDSCConfig
    $ConfigurationScript += "    }"
    $ConfigurationScript += "}"

    Write-Information "Setting Configuration Data..."

    $NonConfigData = @{
        ADConfig = @{
            OUs = $OUs
        }
    }

    $ConfigurationScript += ""
    $ConfigurationScript += "$Script:configName -ConfigurationData `$PSScriptRoot\ConfigurationData.psd1"

    $ConfigData = New-ConfigurationData -NonConfigData $NonConfigData

    $global:test = $ConfigurationScript
    Return [PSCustomObject]@{
        ConfigurationData   = $ConfigData
        ConfigurationScript = $ConfigurationScript -Join "`r`n"
    }
}

#region Reverse Functions
function Read-OUs {
    param (
        [parameter(Mandatory)]
        [System.String[]]
        $BaseSearch
    )

    $module = Resolve-Path ( join-path $Script:DSCPath "\DSCResources\MSFT_xADOrganizationalUnit\MSFT_xADOrganizationalUnit.psm1")
    Import-Module $module
    $params = Get-DSCFakeParameters -ModulePath $module

    $ADInfo = Read-ADInfo

    $OutputOUs = @()

    #Create OU ConfigurationData
    foreach ($BaseDN in $BaseSearch) {
        $OUs = Get-ADOrganizationalUnit -SearchBase $BaseDN -Filter *
        foreach ($OU in $OUs) {
            $params.Name = $OU.Name
            $params.Path = $OU.DistinguishedName.Replace("OU=$($OU.Name),", "")

            $Results = Get-TargetResource @params

            $Results.Add("DSCResourceId", [Guid]::NewGuid())
            $Results.Add("DistinguishedName", $OU.DistinguishedName)

            $OutputOUs += $Results
        }
    }

    #Set Dependencies
    foreach ($OU in $OutputOUs) {
        $ParentOU = $OutputOUs.where( {$OU.Path -eq $_.DistinguishedName})
        if ($ParentOU) {
            $OU.Add("DependsOn", @("[xADOrganizationalUnit]$($ParentOU.DSCResourceId)"))
        }
    }

    Return $OutputOUs
}
#endregion

function Import-ReverseDSC {
    $ReverseDSCModule = "ReverseDSC.Core.psm1"
    $module = (Join-Path -Path $PSScriptRoot -ChildPath $ReverseDSCModule -Resolve -ErrorAction SilentlyContinue)
    if ($module -eq $null) {
        $module = "ReverseDSC"
    }
    Import-Module -Name $module -Force
}

function Get-DSCDependentModules {
    $DependentModuleCommands = @()

    $Script:DSCModulesImports.Foreach( {
            $Command = "    Import-DSCResource -ModuleName $($_.Name)"

            if ($_.Version -ne "*" -and $_.Version -ne "") {
                $Command += " -ModuleVersion $($_.Version)"
            }
            $DependentModuleCommands += $Command
        })

    return $DependentModuleCommands
}

function New-ConfigurationData {
    param(
        [hashtable]
        $NonConfigData
    )

    $ConfigData = @{
        AllNodes = @(
            @{
                NodeName                    = "*"
                PSDscAllowPlainTextPassword = $true
                PSDscAllowDomainUser        = $true
            }
        )
    }

    $ConfigData.AllNodes += @{
        Nodename = $env:COMPUTERNAME
    }

    $NonConfigData.Keys.ForEach( {
            $ConfigData.Add($_, $NonConfigData[$_])
        })

    Return $ConfigData
}

function New-ConfigurationScriptComments {
    $Comments = @('<#')

    try {
        $currentScript = Test-ScriptFileInfo $Script:MyInvocation.MyCommand.Path
        $Comments += "Generated with xActiveDirectory.Reverse Version: $($currentScript.Version.ToString())"
    } catch {
        $Comments += "Generated with xActiveDirectory.Reverse Version: N/A"
    }

    $ADInfo = Read-ADInfo

    $Comments += "AD Infrastructure"
    $Comments += "ForestMode: $($ADInfo.Forest.ForestMode)"
    $Comments += "DomainMode: $($ADInfo.Domain.DomainMode)"

    $Comments += '#>'

    Return $Comments

}

function Read-ADInfo {
    return [PSCustomObject]@{
        Forest = (Get-ADForest)
        Domain = (Get-ADDomain)
    }
}

function New-LCMConfig {
    $LCMConfig = @("        LocalConfigurationManager {")
    $LCMConfig += "            RebootNodeIfNeeded = `$True"
    $LCMConfig += "       }"

    Return $LCMConfig
}

function New-OUDSCConfig {
    $OUDSCConfig = @("        `$ConfigurationData.ADConfig.OUs.Foreach({")
    $OUDSCConfig += "            if(`$DomainCredential) {"
    $OUDSCConfig += "                xADOrganizationalUnit `$_.DSCResourceId {"
    $OUDSCConfig += "                    Name = `$_.Name"
    $OUDSCConfig += "                    Description = `$_.Description"
    $OUDSCConfig += "                    Path = `$_.Path"
    $OUDSCConfig += "                    Ensure = `$_.Ensure"
    $OUDSCConfig += "                    ProtectedFromAccidentalDeletion = `$_.ProtectedFromAccidentalDeletion"
    $OUDSCConfig += "                    Credential = `$DomainCredential"
    $OUDSCConfig += "                }"
    $OUDSCConfig += "            } else {"
    $OUDSCConfig += "                xADOrganizationalUnit `$_.DSCResourceId {"
    $OUDSCConfig += "                    Name = `$_.Name"
    $OUDSCConfig += "                    Description = `$_.Description"
    $OUDSCConfig += "                    Path = `$_.Path"
    $OUDSCConfig += "                    Ensure = `$_.Ensure"
    $OUDSCConfig += "                    ProtectedFromAccidentalDeletion = `$_.ProtectedFromAccidentalDeletion"
    $OUDSCConfig += "                }"
    $OUDSCConfig += "            }"
    $OUDSCConfig += "        })"

    Return $OUDSCConfig
}

function Get-ReverseDSC {
    param (
        [parameter(Mandatory)]
        [System.String[]]
        $BaseSearch,

        [parameter()]
        [string]
        $OutputPath
    )

    $Configuration = Orchestrator -BaseSearch $BaseSearch

    $fileName = "xActiveDirectory.DSC.ps1"

    if ([string]::IsNullOrEmpty($OutputPath)) {
        $OutputPath = Read-Host "Please enter the full path of the output folder for DSC Configuration (will be created as necessary)"
    }

    while (!(Test-Path -Path $OutputPath -PathType Container -ErrorAction SilentlyContinue)) {
        try {
            Write-Output "Directory `"$OutputPath`" doesn't exist; creating..."
            New-Item -Path $OutputPath -ItemType Directory | Out-Null
            if ($?) {break}
        } catch {
            Write-Warning "$($_.Exception.Message)"
            Write-Warning "Could not create folder $OutputPath!"
        }
        $OutputPath = Read-Host "Please Enter Output Folder for DSC Configuration (Will be Created as Necessary)"
    }

    $Configuration.ConfigurationData | Export-PSData (Join-Path $OutputPath "ConfigurationData.psd1") | Out-Null

    $Configuration.ConfigurationScript | Out-File (Join-Path $OutputPath $FileName) -Encoding default
}

Get-ReverseDSC @PSBoundParameters
