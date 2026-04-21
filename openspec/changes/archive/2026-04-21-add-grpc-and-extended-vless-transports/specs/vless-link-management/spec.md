## MODIFIED Requirements

### Requirement: System validates VLESS link input before saving
The system SHALL validate the VLESS link before persisting it and SHALL reject malformed or unsupported configurations with an explicit error.

#### Scenario: Accept supported VLESS gRPC link
- **WHEN** the user submits a VLESS link using `type=grpc` with required supported metadata
- **THEN** the system accepts and stores the configuration

#### Scenario: Accept supported VLESS xHTTP link
- **WHEN** the user submits a VLESS link using `type=xhttp` with supported metadata
- **THEN** the system accepts and stores the configuration

#### Scenario: Accept supported VLESS raw link
- **WHEN** the user submits a VLESS link using `type=raw`
- **THEN** the system accepts and stores the configuration
