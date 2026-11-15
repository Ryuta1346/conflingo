import Testing

// These suites share NSApplication's windows, focus, and accessibility state.
// Serializing each child alone does not isolate it from the other UI suites.
@Suite(.serialized)
struct AppKitIntegrationTests {}
