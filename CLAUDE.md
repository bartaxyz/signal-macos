# Signal macOS - Native SwiftUI Client

## Project Overview
Build a native macOS Signal messenger client using SwiftUI with signal-cli as the backend.

## Architecture
- **Frontend:** SwiftUI, macOS 26+ (latest only)
- **Backend:** signal-cli (installed at /usr/local/bin/signal-cli) running as a subprocess in JSON-RPC mode
- **Language:** Swift 6.2+
- **License:** AGPL-3.0

## What to Build (Prototype)
Build a working prototype that proves this architecture is viable. Focus on:

1. **Xcode project setup** - Swift Package, not CocoaPods. Single macOS app target.
2. **signal-cli process manager** - Start signal-cli in JSON-RPC daemon mode as a subprocess. Handle lifecycle (start with app, stop on quit). Parse JSON-RPC responses.
3. **Device linking flow** - Generate a linking URI from signal-cli (`signal-cli link`), display it as a QR code in the app using CoreImage CIQRCodeGenerator. Handle the callback when linking succeeds.
4. **Conversation list** - After linking, fetch contacts and conversations. Display in a sidebar.
5. **Message display** - Show messages for selected conversation in a chat bubble UI.
6. **Send messages** - Text input + send via signal-cli.
7. **Receive messages** - Listen for incoming messages from signal-cli daemon, update UI in real-time.

## signal-cli Usage
- `signal-cli link -n "Signal macOS"` — generates a linking URI (tsdevice:/?uuid=...&pub_key=...)
- `signal-cli -a ACCOUNT daemon --json` — starts JSON-RPC daemon mode, reads/writes JSON on stdin/stdout
- `signal-cli -a ACCOUNT receive --json` — one-shot receive
- `signal-cli -a ACCOUNT send -m "message" RECIPIENT` — send message

## Key Constraints
- NO dependency on Signal Desktop (this replaces it)
- NO CocoaPods — use Swift Package Manager only
- macOS 26+ only (use latest APIs freely)
- Keep it simple — this is a prototype to verify feasibility
- Create proper Xcode project structure (not just loose .swift files)

## File Structure
```
SignalMacOS/
├── Package.swift (or .xcodeproj)
├── Sources/
│   ├── App/
│   │   └── SignalMacOSApp.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── LinkDeviceView.swift
│   │   ├── ConversationListView.swift
│   │   └── MessageView.swift
│   ├── Services/
│   │   ├── SignalCLIService.swift  (process management + JSON-RPC)
│   │   └── SignalStore.swift       (app state)
│   └── Models/
│       ├── Conversation.swift
│       └── Message.swift
```

## After Building
- Test that the app compiles with `xcodebuild`
- Commit all changes
- Push to origin

When completely finished, run this command to notify me:
openclaw system event --text "Done: Signal macOS prototype built - SwiftUI app with signal-cli backend, device linking QR flow, conversation list, message view, send/receive" --mode now
