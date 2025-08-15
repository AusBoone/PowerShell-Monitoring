# Pester tests verifying the event logging functionality of MonitoringTools.
#
# These tests mock Windows event retrieval to simulate scenarios where
# multiple events share an identical timestamp. The Log-EventData function
# should advance its internal marker to avoid writing duplicates when run
# repeatedly. The tests ensure that only unique events are recorded across
# successive invocations.

BeforeAll {
    # Load the MonitoringTools module so the function under test is available.
    Import-Module "$PSScriptRoot/../MonitoringTools.psd1"
}

Describe 'Log-EventData duplicate handling' {
    It 'avoids writing duplicate events when timestamps match' {
        # Create two mock events with the exact same creation time.
        $timestamp = Get-Date
        $mockEvents = @(
            [pscustomobject]@{TimeCreated=$timestamp; Id=1; LevelDisplayName='Error'; Message='first'},
            [pscustomobject]@{TimeCreated=$timestamp; Id=2; LevelDisplayName='Error'; Message='second'}
        )

        # Mock Get-WinEvent so the function receives the mock events when the
        # requested StartTime is earlier than or equal to the test timestamp.
        Mock Get-WinEvent {
            param($FilterHashTable)
            if ($FilterHashTable.StartTime -le $using:timestamp) {
                return $using:mockEvents
            }
            return @()
        }

        # Use a temporary file for logging so the test does not touch real data.
        $tempFile = New-TemporaryFile

        # Initialise the module's lastEventTime to the timestamp of the mock
        # events. The first run should pick them up, and the second run should
        # skip them because of the one-millisecond offset applied by the code.
        InModuleScope MonitoringTools {
            $script:lastEventTime = $using:timestamp
        }

        # First invocation writes the events to disk. Record the resulting line
        # count so we can verify that the second invocation does not append
        # duplicates. Export-Csv writes a header line when the file is created,
        # so the count includes one extra line.
        Log-EventData -EventLog $tempFile.FullName
        $initialLines = (Get-Content $tempFile.FullName).Length

        # Second invocation should not append the same events because the start
        # time moves forward by one millisecond. The line count should remain
        # unchanged if duplicates are correctly avoided.
        Log-EventData -EventLog $tempFile.FullName
        $afterLines = (Get-Content $tempFile.FullName).Length

        $afterLines | Should -Be $initialLines
    }
}
