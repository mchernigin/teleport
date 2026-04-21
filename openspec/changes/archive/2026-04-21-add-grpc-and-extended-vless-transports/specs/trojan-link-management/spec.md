## MODIFIED Requirements

### Requirement: User can add a Trojan link
The system SHALL allow the user to input a Trojan share link and save it as a selectable saved connection configuration.

#### Scenario: Save valid Trojan gRPC link
- **WHEN** the user enters a syntactically valid Trojan link using TLS and `type=grpc`
- **THEN** the system stores it as a saved connection configuration
