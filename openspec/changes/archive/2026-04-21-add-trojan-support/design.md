## Context

Teleport is already a working macOS menu bar client that imports one VLESS share link, persists the active configuration locally, generates an Xray config, launches a bundled Xray runtime, and toggles macOS system proxy settings. Adding Trojan support is not a standalone feature bolted onto an empty codebase; it is an extension of an existing single-profile connection pipeline that is currently too VLESS-specific in its naming, model shape, and config generation.

The main technical challenge is not process management or proxy control, which already exist, but representing more than one connection protocol cleanly without turning the code into protocol-specific branches everywhere. The design should preserve the current one-active-configuration workflow while creating a protocol-aware connection model that can support Trojan now and additional Xray-backed protocols later.

## Goals / Non-Goals

**Goals:**
- Allow users to import and save a supported Trojan share link as the active connection configuration.
- Preserve the current menu bar–only workflow and one-active-profile v1 constraints.
- Refactor the connection model so the app can represent either VLESS or Trojan in one normalized structure.
- Generate correct Xray outbound configuration for Trojan using the existing bundled runtime and local proxy flow.
- Update validation and UI copy so the app is no longer misleadingly VLESS-only.
- Fail clearly on unsupported Trojan variants rather than silently generating broken configs.

**Non-Goals:**
- Multiple saved profiles or protocol switching between several stored connections.
- Broad support for all Trojan transports and every Xray link variant in the first Trojan release.
- New runtime management architecture, new UI surfaces, or changes to how system proxy is toggled.
- Replacing Xray or introducing a second tunneling engine.

## Decisions

### 1. Replace the VLESS-specific top-level connection model with a protocol-aware connection model
The app will introduce a normalized active connection model with a protocol discriminator and protocol-specific authentication/settings fields. Shared properties such as host, port, transport, server name, TLS/Reality-related metadata, and display name will remain common, while protocol-specific values (for example VLESS UUID/flow versus Trojan password) will live in protocol-specific substructures or enum-associated values.

**Rationale:** Trojan support touches persistence, parsing, display, and config generation. A protocol-aware model prevents repeated protocol checks from leaking through the whole app.

**Alternatives considered:**
- Add a second parallel Trojan model beside the VLESS model: fast initially, but increases duplication and future maintenance cost.
- Store raw links only and generate everything dynamically: weaker validation and harder debugging.

### 2. Keep import UX protocol-agnostic and infer protocol from the link scheme
The UI will continue to offer a single link input field and save action, but copy will change from VLESS-specific wording to neutral connection-link wording. The parser will route by scheme (`vless://`, `trojan://`) and produce the normalized connection model.

**Rationale:** The current lightweight UX is a strength; supporting Trojan should not require a more complex protocol picker unless ambiguity exists.

**Alternatives considered:**
- Add an explicit protocol selector: unnecessary for share-link imports because the scheme already identifies the protocol.

### 3. Scope first Trojan support to common TLS and Reality share-link shapes and validate unsupported variants explicitly
The first Trojan release will target the common deployable Trojan link shapes needed for practical use with Teleport: standard TLS-based Trojan links and Reality-backed Trojan links that include the required Reality metadata. Validation should explicitly reject unsupported transports, missing required fields, or unsupported security combinations.

**Rationale:** Trojan link support can expand quickly in complexity; supporting the two most practical shapes while still constraining variants is safer and more testable.

**Alternatives considered:**
- Attempt full Trojan/Xray compatibility immediately: high implementation and test burden.

### 4. Extend Xray outbound generation through protocol-specific builders behind one runtime-config writer
The Xray config writer will remain the single entry point for local inbound and routing configuration, but outbound generation will branch based on the normalized connection protocol. Shared inbound, routing, and asset/runtime management stays unchanged.

**Rationale:** Most runtime config structure is shared; only outbound details differ meaningfully between VLESS and Trojan.

**Alternatives considered:**
- Separate config writers per protocol end-to-end: more duplication and more chances for divergence in shared config.

### 5. Preserve backward compatibility by reparsing persisted raw links into the new normalized model
On launch, the app will continue restoring the active configuration from stored state, but it should rebuild the normalized model from the raw link when possible. This allows existing VLESS users to migrate naturally to the new model without manual re-entry.

**Rationale:** The app already stores the raw link, which is the most stable migration source.

**Alternatives considered:**
- One-time migration from stored decoded fields only: more fragile because older persisted shapes may diverge from the new model.

## Risks / Trade-offs

- [Model refactor could introduce regressions in existing VLESS behavior] → Mitigation: keep protocol-specific parsing/config tests for both VLESS and Trojan and preserve raw-link reparse on startup.
- [Trojan link variants in the wild may exceed the supported subset] → Mitigation: fail with explicit unsupported-configuration errors rather than best-effort misconfiguration.
- [Trojan Reality links require additional metadata and stricter mapping] → Mitigation: validate required Reality parameters explicitly and cover the generated Xray config with focused verification.
- [UI becomes slightly more generic and less protocol-specific] → Mitigation: show the resolved saved protocol and display name so users still understand what is active.
- [Protocol-aware config generation increases branching in one component] → Mitigation: isolate outbound construction into protocol-specific helper builders behind one config writer entry point.

## Migration Plan

- Introduce the normalized protocol-aware connection model alongside raw-link-based reparse support.
- Update persistence loading so existing saved VLESS links restore into the new model automatically.
- Update UI text and validation messages to use protocol-neutral wording.
- Add Trojan parsing/config generation tests before or alongside the refactor to protect existing behavior.

## Open Questions

- Which Trojan transports are explicitly in scope for the first implementation beyond TLS/Reality over TCP: should WS remain supported only for TLS-backed Trojan and not for Reality-backed Trojan?
- Should the UI expose the detected protocol label in the status section for better visibility?
- Are there any user expectations around preserving old error wording that mention VLESS specifically, or can all validation move immediately to generic connection wording?
