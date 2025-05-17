import SwiftUI
import CoreNFC

struct ContentView: View {
    @State private var message = "Ready to write Amiibo data"
    @State private var showingFilePicker = false
    @State private var amiiboData: Data?

    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .padding()

            Button("Select Amiibo .bin File") {
                showingFilePicker = true
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        if let data = try? Data(contentsOf: url) {
                            amiiboData = data
                            message = "Amiibo file loaded, tap your tag to write"
                        } else {
                            message = "Failed to read file"
                        }
                    }
                case .failure(let error):
                    message = "File selection error: \(error.localizedDescription)"
                }
            }

            Button("Write to NFC Tag") {
                if let data = amiiboData {
                    AmiiboNFCWriter.shared.write(data: data) { success, error in
                        if success {
                            message = "Successfully wrote Amiibo!"
                        } else {
                            message = "Failed to write NFC tag: \(error?.localizedDescription ?? "Unknown error")"
                        }
                    }
                } else {
                    message = "No Amiibo data loaded"
                }
            }
            .disabled(amiiboData == nil)
        }
        .padding()
    }
}

class AmiiboNFCWriter: NSObject, NFCNDEFReaderSessionDelegate {
    static let shared = AmiiboNFCWriter()

    private var session: NFCNDEFReaderSession?
    private var dataToWrite: Data?
    private var completion: ((Bool, Error?) -> Void)?

    func write(data: Data, completion: @escaping (Bool, Error?) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion(false, NSError(domain: "NFC", code: 0, userInfo: [NSLocalizedDescriptionKey: "NFC not available"]))
            return
        }
        self.dataToWrite = data
        self.completion = completion
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near the Amiibo tag to write"
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        completion?(false, error)
        self.session = nil
        self.dataToWrite = nil
        self.completion = nil
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        if tags.count > 1 {
            session.alertMessage = "More than one tag detected. Please present only one tag."
            session.restartPolling()
            return
        }
        let tag = tags.first!

        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                self.completion?(false, error)
                return
            }

            tag.queryNDEFStatus { (status, capacity, error) in
                if status == .readWrite {
                    if let dataToWrite = self.dataToWrite {
                        let payload = NFCNDEFPayload(format: .unknown, type: Data(), identifier: Data(), payload: dataToWrite)
                        let message = NFCNDEFMessage(records: [payload])
                        tag.writeNDEF(message) { error in
                            if let error = error {
                                session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
                                self.completion?(false, error)
                            } else {
                                session.alertMessage = "Write successful!"
                                session.invalidate()
                                self.completion?(true, nil)
                            }
                        }
                    } else {
                        session.invalidate(errorMessage: "No data to write")
                        self.completion?(false, NSError(domain: "NFC", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                    }
                } else {
                    session.invalidate(errorMessage: "Tag is not writable")
                    self.completion?(false, NSError(domain: "NFC", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tag not writable"]))
                }
            }
        }
    }
}
