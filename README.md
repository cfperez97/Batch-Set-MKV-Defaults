# Batch Set MKV Defaults

A PowerShell script for batch-setting the default audio and subtitle tracks across a folder of `.mkv` files (e.g. a TV show season) using [MKVToolNix](https://mkvtoolnix.download/).

Instead of opening each episode individually to set the default audio/subtitle track, this script reads the track layout from the first file, lets you pick a default audio and/or subtitle track once, and applies that choice to every `.mkv` file in the folder.

## Requirements

- [MKVToolNix](https://mkvtoolnix.download/) installed, with `mkvmerge` and `mkvpropedit` available in your `PATH`.
- Windows PowerShell.
- All `.mkv` files in the target folder must share the same audio and subtitle track layout (same number/order of tracks), since track selection is based on a single scan of the first file.

## Usage

Run without arguments to be prompted for a folder (defaults to the current directory):

```powershell
.\batch_set_mkv_defaults.ps1
```

Or pass a folder path directly:

```powershell
.\batch_set_mkv_defaults.ps1 -folderPath "C:\Path\To\MKV\Files"
```

### What it does

1. Scans the target folder (non-recursively) for `.mkv` files.
2. Analyzes the first file with `mkvmerge -J` and displays all audio and subtitle tracks (ID, type, language, name, current default status).
3. Prompts you to choose:
   - An **audio track ID** to set as default (or `none` to clear all defaults, or `skip`/Enter to leave audio untouched).
   - A **subtitle track ID** to set as default (or `none`/`skip` as above).
4. Shows a summary of the changes that will be made and asks for confirmation.
5. Runs `mkvpropedit` on every `.mkv` file in the folder, setting the chosen track as default (and clearing the default/forced flags on the others).
6. Re-analyzes the first file and prints the resulting default tracks so you can confirm the change took effect.

## Notes

- Track IDs shown are `mkvmerge`'s 0-based global track IDs; the script automatically converts them to `mkvpropedit`'s 1-based indexing internally.
- The script only modifies files directly inside the given folder (subdirectories are not searched).
- No files are modified until you confirm the summary of changes.