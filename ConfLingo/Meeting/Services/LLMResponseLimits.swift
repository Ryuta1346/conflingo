enum LLMResponseLimits {
    // SSE envelopes and search metadata share a finite budget, separate from answer content.
    static let wireBytes = 2 * 1_024 * 1_024
    static let eventBytes = 65_536
    static let payloadBytes = 65_536
}
