import Foundation

/// Which hotkey the user held: raw dictation vs. AI-cleaned dictation.
public enum RecordingMode: Equatable {
    case noAI
    case withAI
}

/// Detected intent for a transcription, derived from the text + active app.
/// Drives which AI prompt (if any) runs and how the result is delivered.
public enum DictationContext: Equatable {
    case `default`
    case codePrompt
    case formalChat
    case aiQuestion(trigger: String)
    case translate(language: String)
}
