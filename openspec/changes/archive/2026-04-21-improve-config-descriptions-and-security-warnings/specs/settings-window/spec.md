## MODIFIED Requirements

### Requirement: Settings window shows saved connections and selection state
The Settings window SHALL present saved manual and imported connections in a way that helps the user distinguish their protocol and safety-relevant traits.

#### Scenario: Show descriptive connection summary
- **WHEN** the user views a saved or imported connection in Settings
- **THEN** the row shows a descriptive summary of protocol, security, transport, and notable supported traits instead of only the bare protocol name

#### Scenario: Warn about insecure configuration
- **WHEN** the user views a saved or imported connection that disables encryption or enables insecure TLS validation
- **THEN** the row shows a visible warning marker indicating the config is not secure
