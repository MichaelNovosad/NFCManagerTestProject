//
//  NFCManager.swift
//  NFCTest
//
//  Created by Michael Novosad on 05.04.2025.
//

import Foundation
import CoreNFC
import Combine

// Make sure this class is thread-safe if accessed from multiple threads,
// but for this simple example, UI interactions will trigger it on the main thread.
class NFCManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {

    @Published var receivedMessage: String = "Ready to Receive"
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false

    private var nfcSession: NFCNDEFReaderSession?
    private var messageToSend: NFCNDEFMessage?

    // MARK: - Public Methods (Called from UI)

    /// Starts a session to READ an NDEF message from another device/tag.
    func startNFCReading() {
        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC Reading not available on this device.")
            showAlert(message: "NFC Reading is not available on this device.")
            return
        }
        // Invalidate previous session if any
        nfcSession?.invalidate()
        // Create a new session. Delegate is self, queue is nil (main queue), invalidateAfterFirstRead is true.
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        nfcSession?.alertMessage = "Hold your iPhone near the other device to receive."
        nfcSession?.begin()
        print("NFC Reading Session Started")
    }

    /// Starts a session to WRITE an NDEF message to another device/tag.
    func startNFCWriting(text: String) {
        guard NFCNDEFReaderSession.readingAvailable else { // Writing also requires reading capability check
             print("NFC Writing not available on this device.")
             showAlert(message: "NFC Writing is not available on this device.")
             return
         }

        // 1. Create the NDEF Payload from the text
        //    TNF = Type Name Format (0x01 = Well Known)
        //    Type = RTD (Record Type Definition) Text ("T" = 0x54)
        //    Identifier = Empty
        //    Payload = Status Byte (language code length) + Language Code (e.g., "en") + Text
        let languageCode = "en" // Or get device language
        let textData = Data(text.utf8)
        let languageCodeData = Data(languageCode.utf8)
        // Status Byte: Bit 7=0 (UTF-8), Bits 5-0 = Language Code Length
        let statusByte = UInt8(languageCodeData.count & 0x3F)
        var payloadData = Data([statusByte])
        payloadData.append(languageCodeData)
        payloadData.append(textData)

        let payload = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: Data("T".utf8), // RTD_TEXT type
            identifier: Data(),
            payload: payloadData
        )

        // 2. Store the message to be sent when a tag is detected
        self.messageToSend = NFCNDEFMessage(records: [payload])

        // 3. Start the NFC Session
        // Invalidate previous session if any
        nfcSession?.invalidate()
        // Create a new session for reading/writing.
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false) // Don't invalidate immediately for writing
        nfcSession?.alertMessage = "Hold your iPhone near the other device to send."
        nfcSession?.begin()
        print("NFC Writing Session Started - Waiting for tag...")
    }

    // MARK: - NFCNDEFReaderSessionDelegate Methods

    // Called when the session finds NDEF messages. Used for READING.
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        print("NFC Session detected NDEF messages.")
        guard let firstMessage = messages.first, // Process only the first message
              let firstRecord = firstMessage.records.first, // Process only the first record
              firstRecord.typeNameFormat == .nfcWellKnown,
              let payloadText = decodeNDEFPayload(payload: firstRecord)
        else {
            print("Message format not supported or empty.")
            session.invalidate(errorMessage: "Received data format not supported.")
            showAlert(message: "Received data format not supported.")
            return
        }

        DispatchQueue.main.async {
            self.receivedMessage = payloadText
            print("Received Message: \(payloadText)")
            // Session invalidates automatically because invalidateAfterFirstRead=true for reading
        }
        // No need to manually invalidate for reading if invalidateAfterFirstRead is true
    }

    // Called when the session detects compatible tags. Used for WRITING.
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        print("NFC Session detected tags for writing.")
        guard let tag = tags.first else {
             session.invalidate(errorMessage: "No NDEF tag found.")
             showAlert(message: "No compatible tag found.")
             return
        }
        guard let messageToWrite = self.messageToSend else {
            print("No message prepared for writing.")
            session.invalidate(errorMessage: "Internal error: No message to write.")
            showAlert(message: "Error: No message prepared to send.")
            return
        }

        // Connect to the tag
        session.connect(to: tag) { [weak self] (error: Error?) in
            guard let self = self else { return }
            if let error = error {
                print("Failed to connect to tag: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection failed.")
                self.showAlert(message: "Failed to connect to the other device.")
                return
            }

            // Check tag status and writability
            tag.queryNDEFStatus { (status: NFCNDEFStatus, capacity: Int, error: Error?) in
                if let error = error {
                    print("Failed to query NDEF status: \(error.localizedDescription)")
                    session.invalidate(errorMessage: "Failed to check tag status.")
                    self.showAlert(message: "Failed to check status of the other device.")
                    return
                }

                guard status == .readWrite else {
                    print("Tag is not writable.")
                    session.invalidate(errorMessage: "Device is not ready to receive.")
                    self.showAlert(message: "The other device is not ready to receive.")
                    return
                }

                // Check if message fits
                let messageLength = messageToWrite.length
                 guard messageLength <= capacity else {
                    print("Message too large for tag capacity (\(messageLength) > \(capacity)).")
                    session.invalidate(errorMessage: "Data too large.")
                    self.showAlert(message: "Data is too large to send.")
                    return
                 }

                // Write the message
                tag.writeNDEF(messageToWrite) { (error: Error?) in
                    if let error = error {
                        print("Failed to write NDEF message: \(error.localizedDescription)")
                        session.invalidate(errorMessage: "Write failed.")
                        self.showAlert(message: "Failed to send data.")
                    } else {
                        print("NDEF Message written successfully!")
                        session.alertMessage = "Sent Successfully!"
                        session.invalidate() // Invalidate session after successful write
                        self.showAlert(message: "Data Sent Successfully!")
                        // Clear the message to send after successful write
                        DispatchQueue.main.async {
                             self.messageToSend = nil
                        }
                    }
                }
            }
        }
    }

    // Called when the session becomes active. Optional.
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        print("NFC Session Active")
    }

    // Called when the session is invalidated, either by error or success.
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Check if the error indicates user cancellation or session timeout, which are normal.
        if let nfcError = error as? NFCReaderError,
           (nfcError.code == .readerSessionInvalidationErrorUserCanceled ||
            nfcError.code == .readerSessionInvalidationErrorSessionTimeout) {
            print("NFC Session invalidated normally.")
        } else {
            // Handle other errors
            print("NFC Session invalidated with error: \(error.localizedDescription)")
            showAlert(message: "NFC Session Error: \(error.localizedDescription)")
        }
        // Clean up the session reference
        self.nfcSession = nil
        // Clear any pending message
         DispatchQueue.main.async {
            self.messageToSend = nil
         }
    }

    // MARK: - Helper Methods

    private func decodeNDEFPayload(payload: NFCNDEFPayload) -> String? {
        // Basic text record decoding (RTD_TEXT)
        // Assumes UTF-8 encoding, skips language code byte(s)
        guard payload.payload.count > 0 else { return nil }

        let statusByte = payload.payload[0]
        let languageCodeLength = Int(statusByte & 0x3F) // Get length from bits 0-5

        guard payload.payload.count > 1 + languageCodeLength else { return nil }

        // Extract text data (assuming UTF-8, which is bit 7=0 of status byte)
        let textData = payload.payload.subdata(in: (1 + languageCodeLength)..<payload.payload.count)
        return String(data: textData, encoding: .utf8)
    }

    private func showAlert(message: String) {
         DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
         }
     }
}
