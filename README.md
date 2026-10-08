# Concieasy for iOS

Native SwiftUI operations screens based on the Concieasy web source in `web/concieasy-web-export.zip`. Open `Concieasy/Concieasy.xcodeproj`, choose the shared **Concieasy** scheme, then run on an iPhone or iPad simulator (iOS 16.2 or later).

## Workflows

- Concierge overview, server queue counts, signed-in team sessions, and front-desk alerts.
- Luggage requests, room selection, porter assignment, progress, completion and completed-task history.
- Stored items, scheduled pickups, photographs, editing and collection.
- Valet vehicle check-in, editing, requests now/later, driver assignment, collection outcomes, movement history and departed vehicles.
- Dining, transport, tour and other reservations, with editing and cancellation.
- Handover/FYI notes with date filtering, editing and deletion.
- AYS shortcuts for bags, room moves, car-down requests, guest assistance and front-desk alerts; pending, in-progress, completed and archived boards.

The navy/teal shell, pale backgrounds, white cards, gold accents and task colours follow the recovered web styles. iOS uses system fonts and SF Symbols. The export is truncated at the luggage mascot image; the native app does not depend on its missing assets or web build files.

## Existing backend

`OperationsAPI.baseURL` points at `https://luggage-movement-log.tztm49pksy.chatgpt.site`. Native screens send the same payloads to the existing `/api/*` endpoints. No database, backend, credentials or copied production data are bundled in this app.

Sign in from Workspace or the account menu using your existing Concierge or AYS credentials. The native sign-in form calls `/api/auth` (`login` or `ays-login`), and URLSession retains the server's secure session cookies. Passwords are not saved by the app. Selecting AYS changes the client workspace; it does not grant server permissions. Use the AYS account for requests and an authorised Concierge account for operations.

All scheduling fields use **Pacific/Auckland**, independent of the device's time zone. Luggage completion obtains the server timestamp from `/api/start` and passes that unchanged to `/api/complete`. Storage uploads use the existing multipart contract and R2 image route. Mutations and their audit/notification side effects remain on the existing server. A failed save keeps the form open with its inputs; saves are never queued offline. Background polling pauses while the app is inactive or an editor is open.

User administration, password recovery and CSV downloads remain web workflows. Advanced settings links to the original web settings; Safari has a separate sign-in session. Native handover does not invent a completion action: the exported handover API supports creating, editing and deleting notes, not marking them complete.

## Validation

In Xcode, use **Product → Test** (`⌘U`). The shared scheme includes unit and UI tests. GitHub Actions also runs `xcodebuild test` on a macOS iPhone simulator for pushes to `main` and pull requests. Unit tests use a mock transport and do not write to the live backend.

The Linux cloud environment cannot compile or run SwiftUI/UIKit. Source syntax, project references, scheme XML and request contracts can be checked there, but they do not establish a successful iOS build. Live API validation was also blocked by the cloud environment's network policy. Verify sign-in and the following workflows on your Mac against the intended workspace: an AYS request reaching Concierge, porter completion reaching the AYS completed board, valet collection and movement history, a reservation edit/cancellation, stored-item photo/pickup/collection, and a front-desk alert dismissal. These checks change real workspace records; use designated test records.

After changes are pushed, fetch/pull `main` in Xcode's Source Control menu. Linking the project to GitHub does not automatically pull new commits.
