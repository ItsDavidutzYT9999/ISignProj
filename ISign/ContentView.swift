import SwiftUI
import UniformTypeIdentifiers

class CertManager: ObservableObject {
    @Published var certURL: URL?
}

struct ContentView: View {
    @StateObject private var certManager = CertManager()
    @State private var isDarkMode = true // implicit dark mode

    var body: some View {
        TabView {
            HomeView(isDarkMode: $isDarkMode)
                .environmentObject(certManager)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            CertsView(isDarkMode: $isDarkMode)
                .environmentObject(certManager)
                .tabItem {
                    Label("Certs", systemImage: "key")
                }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}

struct HomeView: View {
    @EnvironmentObject var certManager: CertManager
    @Binding var isDarkMode: Bool

    @State private var ipaURL: URL?
    @State private var showFileImporter = false
    @State private var isSigning = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Button(action: {
                showFileImporter = true
            }) {
                Text(ipaURL == nil ? "Import IPA" : ipaURL!.lastPathComponent)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [UTType(filenameExtension: "ipa")!],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    ipaURL = urls.first
                case .failure(let error):
                    alertMessage = "Failed to import IPA: \(error.localizedDescription)"
                    showAlert = true
                }
            }

            Button(action: {
                signAndInstall()
            }) {
                Text("Sign & Install")
                    .bold()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background((ipaURL == nil || certManager.certURL == nil || isSigning) ? Color.gray : Color.blue)
                    .cornerRadius(10)
            }
            .disabled(ipaURL == nil || certManager.certURL == nil || isSigning)

            if isSigning {
                ProgressView("Signing & Installing...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }

            Spacer()
        }
        .padding()
        .background(isDarkMode ? Color.black : Color.white)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Toggle(isOn: $isDarkMode) {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(isDarkMode ? .yellow : .orange)
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .labelsHidden()
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .navigationTitle("Home")
    }

    func signAndInstall() {
        guard let ipaURL = ipaURL else { return }
        guard let certURL = certManager.certURL else {
            alertMessage = "Certificate is required"
            showAlert = true
            return
        }

        isSigning = true

        let boundary = UUID().uuidString
        var body = Data()

        // IPA file
        if let ipaData = try? Data(contentsOf: ipaURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"ipa\"; filename=\"\(ipaURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(ipaData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Cert file
        if let certData = try? Data(contentsOf: certURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"cert\"; filename=\"\(certURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(certData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = URL(string: "https://yourdomain.com/sign") else {
            alertMessage = "Invalid backend URL"
            showAlert = true
            isSigning = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            DispatchQueue.main.async {
                isSigning = false

                if let error = error {
                    alertMessage = "Upload failed: \(error.localizedDescription)"
                    showAlert = true
                    return
                }

                guard let data = data else {
                    alertMessage = "No response from server"
                    showAlert = true
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let manifestString = json["manifest_url"] as? String,
                       let manifestURL = URL(string: manifestString) {

                        let itmsURL = URL(string: "itms-services://?action=download-manifest&url=\(manifestURL.absoluteString)")!
                        UIApplication.shared.open(itmsURL)
                    } else {
                        alertMessage = "Invalid server response"
                        showAlert = true
                    }
                } catch {
                    alertMessage = "Failed to parse server response"
                    showAlert = true
                }
            }
        }.resume()
    }
}

struct CertsView: View {
    @EnvironmentObject var certManager: CertManager
    @Binding var isDarkMode: Bool

    @State private var showFileImporter = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Button(action: {
                showFileImporter = true
            }) {
                Text(certManager.certURL == nil ? "Import Certificate (.isigncert)" : certManager.certURL!.lastPathComponent)
                    .foregroundColor(isDarkMode ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [UTType(filenameExtension: "isigncert")!],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    certManager.certURL = urls.first
                    alertMessage = "Certificate imported: \(certManager.certURL!.lastPathComponent)"
                    showAlert = true
                case .failure(let error):
                    alertMessage = "Failed to import certificate: \(error.localizedDescription)"
                    showAlert = true
                }
            }

            Spacer()
        }
        .padding()
        .background(isDarkMode ? Color.black : Color.white)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Toggle(isOn: $isDarkMode) {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(isDarkMode ? .yellow : .orange)
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .labelsHidden()
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Certificate"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .navigationTitle("Certs")
    }
}
