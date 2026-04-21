## MODIFIED Requirements

### Requirement: Application provides a settings window
The application SHALL provide a dedicated settings window separate from the menu bar popover.

#### Scenario: Open settings from the menu bar
- **WHEN** the user invokes the Settings action from the menu bar UI
- **THEN** the application opens the settings window

### Requirement: Settings window includes a Connections tab
The settings window SHALL include a Connections tab for managing saved connection configs and subscription sources.

#### Scenario: User opens Connections settings
- **WHEN** the settings window is shown
- **THEN** the system displays a Connections tab with the saved connection list, subscription management controls, and connection-management actions

#### Scenario: Add subscription from Connections settings
- **WHEN** the user enters a valid subscription URL in the Connections tab
- **THEN** the system saves the subscription source and shows the resulting imported entries after fetch completes

#### Scenario: Show subscription fetch failure in Connections settings
- **WHEN** adding or refreshing a subscription source fails
- **THEN** the system shows a visible error in the Connections tab
