/// How the backend answered an upload. Infrastructure maps HTTP statuses and network errors to these.
public enum UploadResult: Hashable, Sendable {
    case accepted
    /// Every event in the batch was already received; nothing new to process.
    case alreadyReceived
    /// The backend doesn't know this device id; register it and try once more.
    case deviceUnknown
    /// Too many uploads lately; try again later.
    case rateLimited
    /// Offline, timed out, or a server error; keep the batch and retry later.
    case failed
}
