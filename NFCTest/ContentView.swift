//
//  ContentView.swift
//  NFCTest
//
//  Created by Michael Novosad on 05.04.2025.
//

import SwiftUI

import SwiftUI

struct ContentView: View {
    // Create and keep alive the NFCManager instance
    @StateObject private var nfcManager = NFCManager()

    // State for the text field
    @State private var textToSend: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("NFC String Transfer")
                    .font(.largeTitle)

                Spacer()

                // Section for Sending
                VStack {
                    Text("Send Data").font(.title2)
                    TextField("Enter text to send", text: $textToSend)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)

                    Button("Send via NFC") {
                        // Generate a random string if field is empty for testing
                        let stringToSend = textToSend.isEmpty ? randomString(length: 10) : textToSend
                        print("Attempting to send: \(stringToSend)")
                        nfcManager.startNFCWriting(text: stringToSend)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                    // Disable if text is empty? Optional.
                    // .disabled(textToSend.isEmpty)
                }

                Divider()

                // Section for Receiving
                VStack {
                    Text("Receive Data").font(.title2)
                    Text("Received:")
                    Text(nfcManager.receivedMessage)
                        .font(.body)
                        .foregroundColor(.gray)
                        .frame(minHeight: 50) // Give it some space
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray))


                    Button("Start Receiving via NFC") {
                         print("Attempting to receive...")
                         nfcManager.startNFCReading()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green) // Different color for receive button
                }

                Spacer()
            }
            .padding()
            .navigationTitle("NFC Demo")
            .navigationBarTitleDisplayMode(.inline)
            // Alert to show messages from NFCManager
            .alert("NFC Info", isPresented: $nfcManager.showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(nfcManager.alertMessage)
            }
        }
    }

    // Helper function for random string generation
    func randomString(length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      return String((0..<length).map{ _ in letters.randomElement()! })
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
