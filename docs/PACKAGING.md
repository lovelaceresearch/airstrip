# Packaging Airstrip

This is the simple path for sending Airstrip to one trusted Mac.

## Build The App

From this folder, run:

```sh
Scripts/package-app.sh
```

The script creates:

```text
dist/Airstrip.zip
dist/Airstrip.dmg
```

Use the DMG for the friendliest install flow.

## Install On Another Mac

1. Send `dist/Airstrip.dmg` to the other Mac.
2. Open the DMG.
3. Drag `Airstrip.app` into `Applications`.
4. Open `Applications`.
5. Right-click `Airstrip.app` and choose `Open`.

The first launch needs right-click Open because this local build is not notarized by Apple. After that, normal double-click launching should work.

## Why Not Just Double-Click Immediately?

This build is for personal sharing. It is not signed with an Apple Developer ID and not notarized. macOS Gatekeeper may block the first launch with a warning like "Apple cannot check it for malicious software."

For real public distribution, Airstrip needs:

1. Apple Developer Program membership.
2. Developer ID Application signing.
3. Notarization through Apple.
4. A stapled notarization ticket on the app or DMG.

That removes most scary first-launch warnings for normal users.

## What To Send With Airstrip

Send Airstrip separately from automation folders.

On the other Mac:

1. Install Airstrip.
2. Open Airstrip.
3. Drag the automation folder into Airstrip.
4. Double-click the imported project.

Airstrip will create project-local Python environments and install declared dependencies on first run.
