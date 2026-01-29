import Foundation

enum SummaryType: String, CaseIterable, Identifiable {
    case executive = "Executive Summary"
    case detailed = "Detailed Summary"
    case actionItems = "Action Items"
    case keyDecisions = "Key Decisions"
    case participants = "Participants"
    case topics = "Topics"
    
    var id: String { rawValue }
    
    var prompt: String {
        switch self {
        case .executive:
            return "Provide a concise executive summary of this meeting."
        case .detailed:
            return "Provide a detailed summary of this meeting."
        case .actionItems:
            return "Extract all action items from this meeting, including who is responsible and deadlines if mentioned."
        case .keyDecisions:
            return "List all key decisions made during this meeting."
        case .participants:
            return "List all participants and their roles/contributions in this meeting."
        case .topics:
            return "Identify and summarize the main topics discussed in this meeting."
        }
    }
}