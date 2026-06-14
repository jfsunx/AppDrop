# AppDrop

AppDrop is a lightweight native macOS app uninstaller. It helps you remove an application bundle together with related user-level files, while keeping the workflow simple, reviewable, and recoverable.

## Features

- Native macOS interface built with Swift and SwiftUI
- English and Simplified Chinese UI based on the system language
- Scans installed apps only when the app list is opened or refreshed
- Scans leftover files only after you select an app
- Calculates app size after selection, keeping the initial app list fast
- Moves selected items to Trash instead of deleting them permanently
- Shows related user-level files such as preferences, caches, containers, logs, saved state, cookies, and support data
- Shows system-level leftovers unchecked by default, so you can review and manually select them
- Labels system-level leftovers by risk, including permission-required and high-risk items
- Detects apps that appear to come from Homebrew Cask or Setapp and shows a source hint
- Shows success and failure details after uninstall
- Shows removable Apple apps while filtering protected system components
- No background daemon, login item, menu bar agent, analytics, or network service

## Installation

Download the latest `AppDrop.app`, then drag it into `/Applications`.

Because current builds are not signed or notarized, macOS Gatekeeper may prevent the app from opening after download. If you trust the downloaded file, remove the quarantine attribute with:

```bash
xattr -dr com.apple.quarantine /Applications/AppDrop.app
```

Then open AppDrop again.

## Permissions

AppDrop works best with access to common Library folders where app leftovers are stored. If some locations are not readable, AppDrop may show a prompt recommending Full Disk Access.

To enable it manually:

1. Open `System Settings`
2. Go to `Privacy & Security`
3. Open `Full Disk Access`
4. Add and enable `AppDrop`
5. Restart AppDrop

When AppDrop uses Finder to move items to Trash, macOS may also ask for Automation permission. Allow it if you want Finder-based Trash fallback to work.

## Usage

1. Open AppDrop
2. Select an app from the list
3. Review the files found for that app
4. Keep or uncheck any items you do not want to remove
5. Click `Uninstall`
6. Confirm moving the selected items to Trash

If something looks wrong, restore the item from Trash before emptying it.

## Build From Source

Requirements:

- macOS
- Xcode 26 or later

Build steps:

1. Open `AppDrop.xcodeproj`
2. Select the `AppDrop` scheme
3. Choose `My Mac`
4. Run with `Command + R`

The app icon source is stored at `AppDrop/appdrop.icon`.

## Safety Notes

AppDrop is intentionally conservative:

- It does not permanently delete files.
- It does not automatically remove protected Apple/system apps.
- It does not install privileged helpers.
- It does not empty Trash for you.

Review selected files carefully before uninstalling, especially when manually selecting system-level items.
