import Foundation

/// Builds a `multipart/form-data` request body. Shared by the STT providers that
/// upload a WAV file (WhisperServer, Groq, OpenAI) — mirrors the `files=`/`data=`
/// shape Python's `requests` produced in `convert_speech_to_text`.
struct MultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// Value for the request's `Content-Type` header.
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// Append a plain text field.
    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    /// Append a binary file part.
    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// Finalize the body with the closing boundary.
    func finished() -> Data {
        var out = body
        out.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return out
    }

    private mutating func append(_ string: String) {
        body.append(string.data(using: .utf8)!)
    }
}
