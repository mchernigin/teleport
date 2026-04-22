## Context

Teleport already persists manual and subscription-imported connections, exposes selection in the menu bar, and performs runtime connect/disconnect through the app view model. What is missing is pre-connection health visibility: the user cannot tell whether a saved endpoint is currently reachable or which server is likely to respond fastest without attempting a full connection.

This feature touches persistence, background work scheduling, and two user surfaces: the Connections settings list and the compact menu bar picker. The design needs to avoid blocking the main actor, avoid launching full Xray sessions just to test servers, and keep the meaning of the displayed latency clear.

## Goals / Non-Goals

**Goals:**
- Track a current health state and latency per saved connection.
- Probe manual and subscription-imported connections using a lightweight mechanism that works with the existing Swift/macOS stack.
- Surface health information in Settings and the menu bar without preventing normal connect/disconnect actions.
- Persist the last known result and checked timestamp so recent results survive relaunch.
- Support user-driven refresh and bounded automatic refresh while the app is running.

**Non-Goals:**
- Guarantee full end-to-end protocol validity for every transport and security mode.
- Implement raw ICMP ping, which is less portable here and less representative for proxy endpoints.
- Continuously monitor every server in real time with aggressive background traffic.
- Auto-switch the active connection to the best server.

## Decisions

### Measure endpoint probe latency, not ICMP ping
The app will treat "ping" as probe latency to the configured server endpoint. A background probe service will attempt a TCP connection to `host:port` with a short timeout and record the elapsed time until connect success or failure. Successful connect time becomes the displayed latency. Failures become an unreachable result with a summarized error.

This approach is the best first implementation because it maps directly to the actual proxy endpoint the app will use, avoids elevated privileges, and works consistently for manual and subscription-imported servers.

**Alternatives considered:**
- ICMP ping. Rejected because it may require different privileges/tooling, is often blocked independently of the proxy service, and can mislead users when TCP is available but ICMP is not.
- Full protocol validation through a temporary Xray session. Rejected for v1 because it is heavier, slower, and complicates probe scheduling and cleanup.

### Keep health state as separate metadata attached to each saved connection
Each saved connection will gain optional health metadata containing status, checked timestamp, latency in milliseconds when available, and a brief failure summary when unavailable. The metadata is persisted alongside the saved connection snapshot.

Keeping this data on the saved connection model allows both Settings and menu bar selection to read a single source of truth without separate lookup tables.

**Alternatives considered:**
- Ephemeral in-memory probe cache only. Rejected because the UI would reset to unknown every launch and lose useful recent results.
- Separate persisted probe store keyed outside the saved connection model. Rejected because it adds lookup complexity with little value at current scale.

### Probe through a dedicated background service with capped concurrency
The app will introduce a probe coordinator in the service/view-model layer that schedules endpoint checks off the main actor and publishes results back to the UI. It will limit concurrent probes, debounce repeated requests for the same connection, and skip checks for fresh results unless the user explicitly refreshes.

This keeps probing from competing excessively with UI work and avoids flooding providers when many subscription entries exist.

**Alternatives considered:**
- Fire probes inline from SwiftUI views. Rejected because view-driven lifecycle is hard to reason about and would cause duplicate work.
- Probe every connection serially on every launch. Rejected because it does not scale and delays useful feedback.

### Use stale-result semantics instead of pretending old data is current
Health results will be considered fresh only for a configurable interval. When the result ages past that interval, the UI may keep showing the last state but must mark it stale or downgrade it to unknown until refreshed. This avoids presenting hours-old latency as current truth.

**Alternatives considered:**
- Always display the last stored value without age. Rejected because it invites incorrect server choice after network conditions change.

### Surface health inline in both Settings and the menu bar, but keep Settings as the richer view
Settings will show the most detail: current state, latency, last checked time, and refresh controls. The menu bar picker will show a compact badge or subtitle for each option so users can avoid obviously unreachable servers without turning the menu into a diagnostics panel.

**Alternatives considered:**
- Show health only in Settings. Rejected because the feature is most useful during quick server selection from the menu bar.
- Show only colors/icons with no latency numbers. Rejected because the user explicitly wants comparative ping information.

## Risks / Trade-offs

- TCP connect success may not prove the full proxy protocol is usable → Label the metric as server latency/health, not full validation, and keep connect as the final authority.
- Large subscription lists can trigger too many probes → Cap concurrency, honor freshness windows, and prioritize selected and recently visible connections first.
- Persisted schema changes can break existing snapshots → Add health metadata as optional fields so older state files still decode cleanly.
- Frequent refreshes can create unnecessary provider traffic → Use manual refresh plus modest automatic refresh intervals instead of tight polling.
- DNS or transient local-network issues may mark many servers unavailable at once → Store failure summaries and checked times so the UI can show that the result reflects the last probe rather than permanent server death.

## Migration Plan

1. Extend the saved connection snapshot with optional health metadata fields defaulting to unknown when absent.
2. Load legacy state without health metadata by treating all existing connections as unprobed.
3. Trigger initial background probes after launch for the selected connection and a bounded subset of saved connections.
4. Persist probe updates incrementally as results arrive.
5. If rollback is needed, older builds should ignore the extra optional fields during decode where possible.

## Open Questions

- What freshness window feels right for this app: for example 5 minutes, 10 minutes, or user-configurable?
- Should the menu bar sort or group by health in addition to showing it, or should ordering remain stable for v1?
- Is a per-subscription "refresh health for all imported servers" action enough, or is a global refresh action also needed?
