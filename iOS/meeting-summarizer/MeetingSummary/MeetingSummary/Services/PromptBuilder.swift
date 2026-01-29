struct PromptBuilder {
    static func build(summaryType: SummaryType, transcript: String) -> String {
        return summaryType.userPrompt + "\n\n" + transcript
    }

    static func templateTranscript() -> String {
        return """
        Alice: Good morning everyone. Let's start with the project update.

        Bob: I've completed the first phase of the development. The new feature is working as expected in our tests.

        Alice: Great, any issues we need to address?

        Bob: There was a minor bug with the UI, but it's fixed now. We'll need to update the documentation.

        Charlie: On the marketing side, we've seen a 20% increase in user engagement after the last campaign.

        Alice: Excellent. Let's schedule a follow-up meeting next week to review the rollout plan.

        Bob: Sounds good.
        """
    }
}