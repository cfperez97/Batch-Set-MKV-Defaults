<#
Batch MKV Default Audio and Subtitle Setter
Requires MKVToolNix (mkvmerge and mkvpropedit) in PATH.
Only works on files with the exact same audio and subtitle tracks across all files (i.e. a season).
Usage:
  .\batch_set_mkv_defaults.ps1
  .\batch_set_mkv_defaults.ps1 -folderPath "C:\Path\To\MKV\Files"
#>

# DEBUG: To take a look at the JSON output from mkvmerge, run the following line
# & mkvmerge -J "mkv_file_name_here.mkv" 2>&1 | Out-String | ConvertFrom-Json | ConvertTo-Json -Depth 6 > json_file_name_here.json

# Accept the folder path in which a user would like to search for and modify .mkv files as a parameter
param(
    [string]$folderPath
)

# Ensure mkvmerge and mkvpropedit are available
try {
    & mkvmerge --version > $null
    & mkvpropedit --version > $null
}
catch {
    Write-Host "Error: mkvmerge or mkvpropedit not found in PATH. Please install MKVToolNix." -ForegroundColor Red
    exit 1
}
Write-Host $folderPath
# If no folder path was provided, ask the user for a folder path
if ([string]::IsNullOrWhiteSpace($folderPath)) {
    Write-Host "Enter the folder path in which you would like to search for .mkv files:" -ForegroundColor Cyan
    Write-Host "(Press Enter to use the current directory)"
    $folderPath = Read-Host "Folder path"
    
    # If $folderPath is still empty, use the current directory
    if ([string]::IsNullOrWhiteSpace($folderPath)) {
        $folderPath = (Get-Location).Path
        Write-Host "`nUsing current directory: $folderPath" -ForegroundColor Yellow
    }
}

# Validate that the folder exists
if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
    Write-Host "`nError: Folder does not exist: $folderPath`n" -ForegroundColor Red
    exit 1
}

Write-Host "`n================================`n" -ForegroundColor Green

# Find .mkv files (no subdirectories)
$mkvFiles = @(Get-ChildItem -LiteralPath $folderPath -Filter "*.mkv" -File)

if ($mkvFiles.Count -eq 0) {
    Write-Host "No .mkv files found in $folderPath`n" -ForegroundColor Yellow
    exit 0
}

# Display found files
Write-Host "Found $($mkvFiles.Count) .mkv file(s) in " -ForegroundColor Cyan -NoNewline
Write-Host "$folderPath`n" -ForegroundColor Yellow
Write-Host "Files found:" -ForegroundColor Green
Write-Host "================================`n" -ForegroundColor Green
foreach ($mkvFile in $mkvFiles) { Write-Host $mkvFile.Name -ForegroundColor Yellow }
Write-Host "`n================================`n" -ForegroundColor Green

# Analyze first file to show available tracks
$firstFile = $mkvFiles[0]
Write-Host "Analyzing first file: " -ForegroundColor Cyan -NoNewline
Write-Host "$($firstFile.Name)`n" -ForegroundColor Yellow

# Extract JSON track info
try {
    $json = & mkvmerge -J "$($firstFile.FullName)" 2>&1 | Out-String
    $info = $json | ConvertFrom-Json
}
catch {
    Write-Host "Failed to read track info from $($firstFile.Name): $_" -ForegroundColor Red
    exit 1
}

# Collect all track information into an array and keep track of max lengths for formatting
$tracks = @()
$maxIDLength = 2
$maxTypeLength = 4
$maxLanguageLength = 8
$maxNameLength = 4
$audioTracks = @()
$subtitleTracks = @()
foreach ($t in $info.tracks) {
    $tracks += [PSCustomObject]@{
        ID       = [int]$t.id
        Type     = $t.type
        # Safely read properties
        Language = if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'language') { $t.properties.language } else { $null }
        Name     = if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'track_name') { $t.properties.track_name } else { $null }
        Default  = if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'default_track' -and $t.properties.default_track) { $true } else { $null }
    }
    $idLength = $t.id.ToString().Length
    if ($idLength -gt $maxIDLength) {
        $maxIDLength = $idLength
    }
    $typeLength = $t.type.Length
    if ($typeLength -gt $maxTypeLength) {
        $maxTypeLength = $typeLength
    }
    if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'language') {
        $languageLength = $t.properties.language.Length
        if ($languageLength -gt $maxLanguageLength) {
            $maxLanguageLength = $languageLength
        }
    }
    if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'track_name') {
        $nameLength = $t.properties.track_name.Length
        if ($nameLength -gt $maxNameLength) {
            $maxNameLength = $nameLength
        }
    }

    # Keep track of audio track and subtitle track IDS for use in the future and adjust for mkvpropedit 1-based indexing
    if ($t.type -eq 'audio') { $audioTracks += [int]$t.id + 1}
    elseif ($t.type -eq 'subtitles') { $subtitleTracks += [int]$t.id + 1}
}

# Display tracks in a custom formatted table
Write-Host "Tracks in this file:" -ForegroundColor Green
Write-Host "================================`n" -ForegroundColor Green
$fmt = "{0,-$maxIDLength} {1,-$maxTypeLength} {2,-$maxLanguageLength} {3,-$maxNameLength} {4,-7}"
Write-Host ($fmt -f "ID","Type","Language","Name","Default")
Write-Host ($fmt -f "--","----","--------","----","-------")
$index = 0
foreach ($t in $tracks) {
    if ($index % 2 -eq 0) {
        Write-Host ($fmt -f $t.ID, $t.Type, $t.Language, $t.Name, $t.Default)
    } else {
        Write-Host ($fmt -f $t.ID, $t.Type, $t.Language, $t.Name, $t.Default) -ForegroundColor DarkGray
    }
    $index++
}
Write-Host "`n================================`n" -ForegroundColor Green

# Helper function to get a valid track input (returns [int], 'none', or 'skip')
function Get-ValidTrackNumber {
    param(
        [string]$Prompt
    )
    while ($true) {
        $userInput = Read-Host $Prompt

        # Check if user pressed Enter or typed 'skip' (do nothing)
        if ([string]::IsNullOrWhiteSpace($userInput) -or $userInput.ToLower() -eq 'skip') {
            return 'skip'
        }

        # Check if user typed 'none' (set all to not default)
        if ($userInput.ToLower() -eq 'none') {
            return 'none'
        }

        # Try to convert to integer
        $refVal = 0
        if ([int]::TryParse($userInput, [ref]$refVal)) {
            return [int]$refVal
        }
        else {
            Write-Host "Invalid input. Enter a numeric track ID, 'none' to set all tracks to not default, or 'skip' to skip." -ForegroundColor Red
        }
    }
}

# Ask user for default audio track (IDs are global track IDs as shown above)
Write-Host "Select the audio track ID to set as default for all files:" -ForegroundColor Cyan
Write-Host "(Enter numeric track ID, 'none' to set all to not default, or 'skip' to skip audio)"
$defaultAudioTrackID = Get-ValidTrackNumber "Audio track ID"

# Ask user for default subtitle track (IDs are global track IDs as shown above)
Write-Host ""
Write-Host "Select the subtitle track ID to set as default for all files:" -ForegroundColor Cyan
Write-Host "(Enter numeric track ID, 'none' to set all to not default, or 'skip' to skip subtitles)"
$defaultSubtitleTrackID = Get-ValidTrackNumber "Subtitle track ID"

# Display a summary of changes
Write-Host "`n================================`n" -ForegroundColor Green
Write-Host "Summary of changes:" -ForegroundColor Cyan

# Display the selected audio track as part of the summary of changes
if ($defaultAudioTrackID -eq 'none') {
    Write-Host " - All audio tracks will be set as NOT default"
} elseif ($defaultAudioTrackID -ne 'skip') {
    $defaultAudioTrack = $tracks | Where-Object { $_.ID -eq $defaultAudioTrackID }
    $defaultAudioTrackLang = if ($defaultAudioTrack) { $defaultAudioTrack.Language } else { "Language unknown" }
    $defaultAudioTrackName = if ($defaultAudioTrack) { $defaultAudioTrack.Name } else { "Track name unknown" }
    Write-Host " - Audio track $defaultAudioTrackID ($defaultAudioTrackLang" -NoNewline
    if ($defaultAudioTrackName) {
        Write-Host " - $defaultAudioTrackName" -NoNewline
    }
    Write-Host ") will be set as default (where present)"
    Write-Host " - All other audio tracks will be set as NOT default"
} else {
    Write-Host " - No audio track will be modified"
}

# Display the selected subtitle track as part of the summary of changes
if ($defaultSubtitleTrackID -eq 'none') {
    Write-Host " - All subtitle tracks will be set as NOT default"
} elseif ($defaultSubtitleTrackID -ne 'skip') {
    $defaultSubtitleTrack = $tracks | Where-Object { $_.ID -eq $defaultSubtitleTrackID }
    $defaultSubtitleTrackLang = if ($defaultSubtitleTrack) { $defaultSubtitleTrack.Language } else { "Language unknown" }
    $defaultSubtitleTrackName = if ($defaultSubtitleTrack) { $defaultSubtitleTrack.Name } else { "Track name unknown" }
    Write-Host " - Subtitle track $defaultSubtitleTrackID ($defaultSubtitleTrackLang" -NoNewline
    if ($defaultSubtitleTrackName) {
        Write-Host " - $defaultSubtitleTrackName" -NoNewline
    }
    Write-Host ") will be set as default (where present)"
    Write-Host " - All other subtitle tracks will be set as NOT default"
} else {
    Write-Host " - No subtitle track will be modified"
}

# Confirm user would like to continue
Write-Host "`nProceed with updating $($mkvFiles.Count) file(s)?" -ForegroundColor Cyan
$confirm = Read-Host "(Enter 'yes' or 'y' to continue or anything else to cancel)"

if ($confirm -notin @('yes','y')) {
    Write-Host "`nOperation cancelled.`n" -ForegroundColor Yellow
    exit 0
}

# Begin processing files and keep track of number of successes and failures
Write-Host "`n================================`n" -ForegroundColor Green
Write-Host "Processing files..." -ForegroundColor Cyan
$successCount = 0
$failCount = 0

# Adjust for mkvpropedit 1-based indexing (only for numeric track IDs)
if ($defaultAudioTrackID -is [int]) {
    $defaultAudioTrackID += 1
}
if ($defaultSubtitleTrackID -is [int]) {
    $defaultSubtitleTrackID += 1
}

# Process each MKV file
foreach ($mkvFile in $mkvFiles) {
    try {
        # Actually mkvpropedit expects file first then options, so build full array
        $mkvpropeditArgs = @($mkvFile.FullName)

        # Add nececessary arguments to set default audio tracks
        if ($defaultAudioTrackID -ne 'skip') {
            if ($audioTracks.Count -eq 0) {
                Write-Host "No audio tracks found in this file."
            } else {
                foreach ($audioTrack in $audioTracks) {
                    if ($audioTrack -eq $defaultAudioTrackID) {
                        $mkvpropeditArgs += "--edit"
                        $mkvpropeditArgs += "track:$audioTrack"
                        $mkvpropeditArgs += "--set"
                        $mkvpropeditArgs += "flag-default=1"
                    } else {
                        $mkvpropeditArgs += "--edit"
                        $mkvpropeditArgs += "track:$audioTrack"
                        $mkvpropeditArgs += "--set"
                        $mkvpropeditArgs += "flag-default=0"
                    }
                    # Set forced display to false for all audio tracks
                    $mkvpropeditArgs += "--edit"
                    $mkvpropeditArgs += "track:$audioTrack"
                    $mkvpropeditArgs += "--set"
                    $mkvpropeditArgs += "flag-forced=0"
                }
            }
        }

        # Add nececessary arguments to set default subtitle tracks
        if ($defaultSubtitleTrackID -ne 'skip') {
            if ($subtitleTracks.Count -eq 0) {
                Write-Host "No subtitle tracks found in this file."
            } else {
                foreach ($subtitleTrack in $subtitleTracks) {
                    if ($subtitleTrack -eq $defaultSubtitleTrackID) {
                        $mkvpropeditArgs += "--edit"
                        $mkvpropeditArgs += "track:$subtitleTrack"
                        $mkvpropeditArgs += "--set"
                        $mkvpropeditArgs += "flag-default=1"
                    } else {
                        $mkvpropeditArgs += "--edit"
                        $mkvpropeditArgs += "track:$subtitleTrack"
                        $mkvpropeditArgs += "--set"
                        $mkvpropeditArgs += "flag-default=0"
                    }
                }
            }
        }

        # Display to the user which file is being processed
        Write-Host "`nProcessing: " -ForegroundColor Cyan -NoNewline
        Write-Host "$($mkvFile.Name)" -ForegroundColor Yellow

        # If there are changes to make, run mkvpropedit
        if ($mkvpropeditArgs.Count -gt 1) {
            # Run mkvpropedit with the constructed arguments and discard output
            & mkvpropedit @mkvpropeditArgs | Out-Null
            
            # Inform user of success
            Write-Host "Successfully updated" -ForegroundColor Green
            $successCount++
        }
        # Inform the the user if there are no track to update
        else {
            Write-Host "No tracks to update for this file"
            $successCount++
        }
    }
    # Catch any errors, notify the user, and increment fail count
    catch {
        Write-Host "Error processing $($mkvFile.Name): $_" -ForegroundColor Red
        $failCount++
    }
}

# Display conclusion summary
Write-Host "`n================================`n" -ForegroundColor Green
Write-Host "Operation complete!" -ForegroundColor Green
Write-Host "Successfully processed: $successCount file(s)" -ForegroundColor Green

if ($failCount -gt 0) {
    Write-Host "Failed: $failCount file(s)" -ForegroundColor Red
}

# Re-analyze first file to show updated tracks
Write-Host "`nRe-analyzing first file: " -ForegroundColor Cyan -NoNewline
Write-Host "$($firstFile.Name)`n" -ForegroundColor Yellow

# Extract JSON track info again
try {
    $json = & mkvmerge -J "$($firstFile.FullName)" 2>&1 | Out-String
    $info = $json | ConvertFrom-Json
}
catch {
    Write-Host "Failed to read track info from $($firstFile.Name): $_" -ForegroundColor Red
    exit 1
}

# Collect all track information into an array and keep track of max lengths for formatting
$tracks = @()
$maxIDLength = 2
$maxTypeLength = 4
$maxLanguageLength = 8
$maxNameLength = 4
$audioTracks = @()
$subtitleTracks = @()
foreach ($t in $info.tracks) {
    if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'default_track' -and $t.properties.default_track) {
        $tracks += [PSCustomObject]@{
            ID       = [int]$t.id
            Type     = $t.type
            # Safely read properties
            Language = if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'language') { $t.properties.language } else { $null }
            Name     = if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'track_name') { $t.properties.track_name } else { $null }
            Default  = if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'default_track' -and $t.properties.default_track) { $true } else { $null }
        }
        $idLength = $t.id.ToString().Length
        if ($idLength -gt $maxIDLength) {
            $maxIDLength = $idLength
        }
        $typeLength = $t.type.Length
        if ($typeLength -gt $maxTypeLength) {
            $maxTypeLength = $typeLength
        }
        if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'language') {
            $languageLength = $t.properties.language.Length
            if ($languageLength -gt $maxLanguageLength) {
                $maxLanguageLength = $languageLength
            }
        }
        if ($t.properties -and $t.properties.PSObject.Properties.Name -contains 'track_name') {
            $nameLength = $t.properties.track_name.Length
            if ($nameLength -gt $maxNameLength) {
                $maxNameLength = $nameLength
            }
        }
    }
}

# Display default tracks in first file after operation
Write-Host "Default tracks in first file after operation:" -ForegroundColor Green
Write-Host "================================`n" -ForegroundColor Green

# Display tracks in a custom formatted table
$fmt = "{0,-$maxIDLength} {1,-$maxTypeLength} {2,-$maxLanguageLength} {3,-$maxNameLength} {4,-7}"
Write-Host ($fmt -f "ID","Type","Language","Name","Default")
Write-Host ($fmt -f "--","----","--------","----","-------")
$index = 0
foreach ($t in $tracks) {
    if ($index % 2 -eq 0) {
        Write-Host ($fmt -f $t.ID, $t.Type, $t.Language, $t.Name, $t.Default)
    } else {
        Write-Host ($fmt -f $t.ID, $t.Type, $t.Language, $t.Name, $t.Default) -ForegroundColor DarkGray
    }
    $index++
}

Write-Host "`n================================`n" -ForegroundColor Green