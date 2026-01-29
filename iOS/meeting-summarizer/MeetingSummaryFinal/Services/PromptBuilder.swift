import Foundation

struct PromptBuilder {
    static func buildPrompt(summaryType: SummaryType, transcript: String) -> String {
        let hasExistingMetadata = transcript.contains("Title:") || 
                                 transcript.contains("Date:") || 
                                 transcript.contains("Time:") || 
                                 transcript.contains("Duration:") || 
                                 transcript.contains("Participants:")
        
        if hasExistingMetadata {
            return "\(summaryType.prompt)\n\n\(transcript)"
        } else {
            let template = """
            Title: [Meeting Title]
            Date: [Date]
            Time: [Time]
            Duration: [Duration]
            Participants: [Participants]
            ----------
            \(transcript)
            """
            return "\(summaryType.prompt)\n\n\(template)"
        }
    }
    
    static func createTemplateTranscript() -> String {
        """
        Title: Weekly Team Meeting
        Date: January 16, 2026
        Time: 2:00 PM - 3:00 PM
        Duration: 1 hour
        Participants: Alex (Manager), Sarah (Developer), Mike (Designer)
        ----------
        **Alex**: Welcome everyone to our weekly team meeting. Let's start with the project updates.
        **Sarah**: I've completed the API integration and it's ready for testing. The endpoints are working as expected.
        **Mike**: The UI mockups are finished and I've sent them to the team for review. The new dashboard design includes real-time analytics.
        **Alex**: Great work everyone. Let's discuss the timeline for the next release. Sarah, when can we start testing?
        **Sarah**: Testing can begin tomorrow morning. I'll need about 2 days for QA.
        **Mike**: I'll need Sarah's API feedback to finalize the frontend components. I can start integrating once testing begins.
        **Alex**: Perfect. Let's aim for a Friday release then. Sarah, please coordinate with QA team. Mike, prepare the deployment checklist.
        **Sarah**: Will do. I'll create test cases today and start testing tomorrow.
        **Mike**: I'll update the deployment documentation and prepare the rollback plan.
        **Alex**: Excellent. Any blockers or concerns?
        **Sarah**: No blockers from my side.
        **Mike**: Everything looks good on my end as well.
        **Alex**: Great meeting everyone. Let's sync up on Thursday for progress updates.
        """
    }
}