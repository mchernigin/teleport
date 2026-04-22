## Why

Teleport lets the user save many manual and subscription-derived connections, but it gives no visibility into which endpoints are currently reachable before attempting to connect. As the number of saved servers grows, users need a lightweight way to compare availability and latency so they can pick a healthy server quickly from Settings or the menu bar.

## What Changes

- Add connection health tracking for saved manual and subscription-imported connections.
- Measure per-connection probe latency and expose a user-visible health state such as unknown, checking, reachable, and unreachable.
- Add user-driven and app-driven probe refresh behavior so health information stays reasonably current without blocking the main UI.
- Show health and latency in the Connections settings list and in the menu bar selection flow.
- Persist the latest known health result with a timestamp so the app can restore recent probe information across relaunches and distinguish stale results from fresh ones.

## Capabilities

### New Capabilities
- `connection-health-monitoring`: Probe saved connection endpoints, classify their current reachability, measure latency, and retain recent health results for the UI.

### Modified Capabilities
- `config-management`: Saved connections must retain health metadata alongside existing manual and subscription-backed configuration data.
- `settings-window`: The Connections tab must show health state, latency, and refresh actions for saved connections and subscriptions.
- `menubar-client`: The menu bar connection picker must expose current health information so the user can choose a reachable server more confidently.

## Impact

- Affected code: app models, persistence snapshot/schema, background services, Settings UI, and menu bar UI.
- Affected systems: endpoint probing, scheduling/debouncing of checks, stale-result handling, and state restoration across relaunches.
- Dependencies: Network.framework or equivalent endpoint-connectivity APIs for low-latency probes without requiring a full Xray session.
