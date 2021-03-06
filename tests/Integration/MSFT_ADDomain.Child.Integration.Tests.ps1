<#
    .SYNOPSIS
        Pester integration test for the ADDomain Resource of the ActiveDirectoryDsc Module
        This Subtest creates a child domain in an existing forest

    .DESCRIPTION
        Verbose/Debug output can be set by running:

        Invoke-pester -Script @{Path='.\MSFT_ADDomain.Child.Integration.Tests.ps1';Parameters=@{Verbose=$true;Debug=$true}}
#>

[CmdletBinding()]
param ()

Set-StrictMode -Version 1.0

$script:dscModuleName = 'ActiveDirectoryDsc'
$script:dscResourceFriendlyName = 'ADDomain'
$script:dscResourceName = "MSFT_$($script:dscResourceFriendlyName)"
$script:subTestName = 'Child'

try
{
    Import-Module -Name DscResource.Test -Force -ErrorAction 'Stop'
}
catch [System.IO.FileNotFoundException]
{
    throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
}

$script:testEnvironment = Initialize-TestEnvironment `
    -DSCModuleName $script:dscModuleName `
    -DSCResourceName $script:dscResourceName `
    -ResourceType 'Mof' `
    -TestType 'Integration'

try
{
    $configFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:dscResourceName).$($script:subTestName).config.ps1"
    . $configFile

    Describe "$($script:dscResourceName).$($script:subTestName)_Integration" {
        BeforeAll {
            $resourceId = "[$($script:dscResourceFriendlyName)]Integration_Test"
        }


        foreach ($testName in $ConfigurationData.AllNodes.Tests.Keys )
        {
            $configurationName = "$($script:dscResourceName)_$($testName)_Config"

            Context ('When using configuration {0}' -f $configurationName) {
                It 'Should compile and apply the MOF without throwing' {
                    {
                        $configurationParameters = @{
                            OutputPath        = $TestDrive
                            # The variable $ConfigurationData was dot-sourced above.
                            ConfigurationData = $ConfigurationData
                        }

                        & $configurationName @configurationParameters

                        $startDscConfigurationParameters = @{
                            Path         = $TestDrive
                            ComputerName = 'localhost'
                            Wait         = $true
                            Force        = $true
                            ErrorAction  = 'Stop'
                        }

                        Start-DscConfiguration @startDscConfigurationParameters
                    } | Should -Not -Throw
                }

                $DscConfigurationStatus = Get-DscConfigurationStatus
                if ($DscConfigurationStatus.RebootRequested)
                {
                    Write-Warning 'A Reboot has been requested by the DSC. Please reboot then re-run the test'
                    Return
                }

                It 'Should be able to call Get-DscConfiguration without throwing' {
                    {
                        $script:currentConfiguration = Get-DscConfiguration -ErrorAction Stop
                    } | Should -Not -Throw
                }

                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq $resourceId
                }

                foreach ($property in $ConfigurationData.AllNodes.Tests.$testName.Keys)
                {
                    It "Should have set the correct $property property" {
                        $resourceCurrentState.$property | Should -Be $ConfigurationData.AllNodes.Tests.$testName.$property
                    }
                }

                It 'Should return $true when Test-DscConfiguration is run' {
                    Test-DscConfiguration | Should -Be 'True'
                }
            }
        }
    }
}
finally
{
    #region FOOTER
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
    #endregion
}
