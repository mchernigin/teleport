## MODIFIED Requirements

### Requirement: System validates VLESS link input before saving
The system SHALL validate the VLESS link before persisting it and SHALL reject malformed or unsupported configurations with an explicit error.

#### Scenario: Accept supported VLESS Reality Vision link
- **WHEN** the user submits a VLESS link with `type=tcp`, `security=reality`, and `flow=xtls-rprx-vision`
- **THEN** the system accepts and stores the configuration

#### Scenario: Accept supported VLESS TLS Vision link
- **WHEN** the user submits a VLESS link with `type=tcp`, `security=tls`, and `flow=xtls-rprx-vision`
- **THEN** the system accepts and stores the configuration

#### Scenario: Reject unsupported VLESS flow combination
- **WHEN** the user submits a syntactically valid VLESS link containing a flow outside the supported transport and security combinations
- **THEN** the system refuses to save it and identifies that the configuration is unsupported
