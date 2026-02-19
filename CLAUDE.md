# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Unified Dashboard** is a SwiftUI iOS app that connects to a Flask backend proxy server. The iOS app is a thin client that communicates exclusively with the Flask backend (never directly to bots or Kalshi). The backend aggregates data from multiple trading bots and provides API endpoints that the iOS app consumes.

- **iOS App**: SwiftUI native app (iOS 17.0+, Xcode 15+)
- **Backend**: Flask server that proxies requests to multiple trading bots and aggregates portfolio data
- **Deployment**: Backend runs in Docker; iOS app is distributed via Xcode

## Architecture

### iOS App (SwiftUI)

The iOS app uses a clear separation of concerns:

```
ios/UnifiedDashboard/
├── UnifiedDashboardApp.swift      # App entry point, manages global state & auth
├── Models/                          # API response models (Codable structs)
│   ├── Bot.swift                   # OverviewResponse, BotStatus
│   └── Capital.swift               # CapitalResponse, Transfer, request bodies
├── Networking/
│   ├── APIClient.swift             # HTTP client abstraction + error handling
│   └── ServerSettings.swift        # Server URL & auth persistence (UserDefaults + Keychain)
├── Views/
│   ├── ContentView.swift           # Root: conditional setup vs main tabs
│   ├── OverviewView.swift          # Portfolio overview with 5-sec auto-refresh
│   ├── CapitalView.swift           # Capital allocation, transfers, history
│   ├── BotDashboardView.swift      # WKWebView per-bot dashboards
│   ├── SettingsView.swift          # Server URL, auth, connection test
│   ├── LockScreenView.swift        # Biometric authentication UI
│   └── Components/                  # Reusable card components
│       ├── BotCardView.swift       # Individual bot status card
│       └── CapitalCardView.swift   # Capital account card
└── Utilities/
    ├── AuthManager.swift           # Face ID / Touch ID + inactivity timeout (5 min)
    ├── KeychainHelper.swift        # Secure credential storage
    ├── Theme.swift                 # Color scheme (dark theme fixed)
    └── Formatters.swift            # Dollar, hex color, timestamp formatters
```

**State Management**: Uses @StateObject/@EnvironmentObject pattern:
- `ServerSettings` (ObservableObject): Persists server URL, username, password. URL validation handles http:// vs https:// based on local/remote detection.
- `AuthManager` (ObservableObject): Tracks biometric lock state + inactivity timeout. Locks on background; unlocks on successful biometric auth.
- Individual view `@State` variables for local UI state.

### Flask Backend

The backend aggregates data from multiple bots and exposes unified API endpoints:

```
├── app.py                  # Main Flask app, proxy routes, API endpoints
├── config.py               # Bot registry (defines BOT_HOST, bot names, endpoints)
├── subaccount_store.py     # Capital allocation persistence
├── kalshi_client.py        # Kalshi API interactions
└── requirements.txt        # Flask, gunicorn, requests, cryptography
```

**Key Endpoints**:
- `GET /api/overview` → Aggregated bot status and total P&L
- `GET /api/capital` → Capital allocations and account balances
- `POST /api/capital/allocate` → Allocate capital to a bot
- `POST /api/capital/transfer` → Transfer between accounts
- `DELETE /api/capital/{id}` → Remove allocation
- `GET /api/capital/transfers` → Transfer history
- `GET /bot/{id}/` → Proxy to per-bot WKWebView dashboard
- `GET /api/capital/{id}/limit` → Per-bot capital limit

**Authentication**: Optional Basic Auth via `PORTAL_USER`/`PORTAL_PASS` environment variables.

## Development Workflow

### Building & Running the iOS App

```bash
# Open Xcode project
open ios/UnifiedDashboard/UnifiedDashboard.xcodeproj

# In Xcode:
# 1. Select target device/simulator
# 2. Cmd+R to build and run
# 3. On first launch, enter server URL (e.g., http://192.168.1.100:8080)
# 4. Optionally add Basic Auth credentials
# 5. Tap "Test Connection" button
```

### Running the Backend Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables (optional)
export PORTAL_USER=admin
export PORTAL_PASS=secret
export BOT_HOST=host.docker.internal  # for Docker; localhost for direct

# Run Flask development server
python app.py

# Or via Docker (if bots are running on host)
docker build -t portal .
docker run -p 8080:8080 \
  -e BOT_HOST=host.docker.internal \
  -e PORTAL_USER=admin \
  -e PORTAL_PASS=secret \
  portal
```

The Flask backend runs on port 8080 by default (see `entrypoint.sh`).

### Testing the iOS App

There are currently no automated tests. Manual testing includes:
- Build and run on simulator or device
- Verify connectivity to backend server
- Test each tab: Overview (polling), Capital (CRUD operations), Bots (WebView), Settings
- Verify biometric lock behavior (enable/disable, inactivity timeout)
- Test error states (server down, auth failure, network error)

## Key Patterns & Conventions

### API Response Models (Models/)

All responses use Codable structs with snake_case mapping (CodingKeys):

```swift
struct ExampleResponse: Codable {
    let totalPnl: Double

    enum CodingKeys: String, CodingKey {
        case totalPnl = "total_pnl"  // Maps to JSON "total_pnl"
    }
}
```

The backend returns JSON; the iOS app decodes it into strongly-typed Swift structs. See `Bot.swift` and `Capital.swift` for examples.

### APIClient Usage

```swift
let client = APIClient(settings: settings)
let overview = try await client.fetchOverview()
```

`APIClient` handles:
- URL construction (baseURL + path)
- Basic Auth header injection (if configured)
- HTTP method dispatch (GET/POST/DELETE)
- Status code validation
- JSON encoding/decoding
- Error translation to `APIError` enum

### State Persistence

- **Server URL**: UserDefaults (non-sensitive)
- **Username/Password**: Keychain (secure storage), with migration from old UserDefaults
- **Biometric Auth State**: Keychain (whether enabled or disabled)

### View Architecture

Views are organized by feature (Overview, Capital, Bots, Settings). Each view:
- Receives shared state via `@EnvironmentObject` (settings, auth)
- Manages local UI state via `@State`
- Fetches data via APIClient in async `.task` or button handlers
- Shows error banners (see `OverviewView` for pattern)

Example polling pattern in `OverviewView`:
```swift
.task {
    while !Task.isCancelled {
        // fetch data
        try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
    }
}
```

## Important Files & Their Roles

| File | Purpose |
|------|---------|
| `UnifiedDashboardApp.swift` | App entry, global environment objects, scene phase handling |
| `ContentView.swift` | Conditional routing: setup vs main tabs |
| `OverviewView.swift` | Portfolio P&L, bot status cards, 5-sec polling |
| `CapitalView.swift` | Allocate, transfer, remove allocation, view history |
| `BotDashboardView.swift` | WKWebView proxy to bot dashboards (per-bot selection) |
| `SettingsView.swift` | Server config, auth credentials, connection test, biometric toggle |
| `APIClient.swift` | HTTP abstraction, request signing, error handling |
| `ServerSettings.swift` | URL/auth persistence + validation logic |
| `AuthManager.swift` | Biometric lock, inactivity timeout, activity tracking |
| `Formatters.swift` | Dollar, hex color, timestamp formatting |
| `App.py` | Flask routes, bot proxying, API endpoints |
| `config.py` | Bot registry + metadata (name, color, port, endpoints) |

## Common Modifications

### Adding a New API Endpoint

1. Add the GET/POST/DELETE method to `APIClient` (following existing patterns)
2. Create a Codable response model in `Models/` if needed
3. Call the new method from a view in an async context
4. Handle `APIError` with `.catch()` or error state variable

### Adding a New Bot

1. Edit `config.py` and add an entry to the `BOTS` dict with port, color, endpoints
2. Ensure the bot is reachable at `BOT_HOST:port`
3. iOS app dynamically fetches and displays bots from `/api/overview` response

### Changing the Theme

Edit `Theme.swift`. The app uses a fixed dark theme (`preferredColorScheme(.dark)`).

### Modifying Capital Operations

Capital flows through `CapitalView` and `CapitalResponse` model. The backend handles persistence in `subaccount_store.py`.

## Network & Security Notes

- **Local Network Access**: `Info.plist` includes `NSAllowsLocalNetworking` to allow http:// on local IPs
- **HTTPS Enforcement**: `ServerSettings` auto-upgrades remote URLs to HTTPS
- **Biometric Lock**: Protects financial data; enabled by default on first launch
- **Inactivity Timeout**: 5 minutes in background; relocks on return to foreground
- **Credential Storage**: Passwords stored in Keychain, not UserDefaults
- **Basic Auth**: Optional; passed as Authorization header to backend and forwarded to bot dashboards

## Debugging Tips

- Use Xcode's Network Link Conditioner to simulate poor connectivity
- Check `ServerSettings.baseURL` property to verify URL construction
- Enable Xcode console logging for network requests (check `APIClient` error cases)
- Verify Flask backend is running: `curl http://server:8080/api/overview` (with Basic Auth if enabled)
- Bot dashboards fail silently if bot is unreachable; check bot ports in `config.py`
- Keychain password issues: Clear app data or simulate reset in Xcode

## Color Scheme & Typography

- **Dark theme** fixed via `preferredColorScheme(.dark)`
- **Portal green** (`Color.portalGreen`) used for tab bar accent
- **Monospace font** (system monospace, 10pt) for tab bar labels
- **Hex color parsing** in `Formatters.swift` (converts bot/account colors to UIColor)
