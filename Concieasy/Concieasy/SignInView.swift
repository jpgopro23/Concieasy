import SwiftUI

struct SignInView: View {
    @ObservedObject var store: OperationsStore
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("Concieasy", systemImage: "bell.fill")
                        .font(.title2.bold()).foregroundStyle(ConciergeStyle.gold)
                    VStack(alignment: .leading, spacing: 20) {
                        Text("TEAM ACCESS").font(.caption2.bold()).tracking(1.8).foregroundStyle(ConciergeStyle.muted)
                        Text("Welcome back").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(ConciergeStyle.navy)
                        Picker("Workspace", selection: Binding(get: { store.area }, set: {
                            store.switchArea($0); username = $0 == .ays ? "ays" : ""; password = ""
                        })) {
                            ForEach(OperationsArea.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        Text("Use the same account as the Concieasy web app.").font(.subheadline).foregroundStyle(ConciergeStyle.muted)
                        TextField(store.area == .ays ? "AYS username" : "Email or username", text: $username)
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).background(ConciergeStyle.background, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("signInUsername")
                        SecureField("Password", text: $password).textContentType(.password)
                            .padding(14).background(ConciergeStyle.background, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("signInPassword")
                        if let error = error { Text(error).font(.subheadline).foregroundStyle(.red) }
                        Button { Task { await signIn() } } label: {
                            HStack { Spacer(); if busy { ProgressView().tint(.white) } else { Text("Sign in").bold() }; Spacer() }
                                .padding(15).foregroundStyle(.white).background(ConciergeStyle.teal, in: RoundedRectangle(cornerRadius: 8))
                        }.disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                        Link("Reset password on the web", destination: OperationsAPI.baseURL)
                            .font(.subheadline.weight(.semibold))
                    }.padding(26).background(.white, in: RoundedRectangle(cornerRadius: 14)).disabled(busy)
                    Text("Concierge · Auckland").font(.caption).foregroundStyle(.white.opacity(0.6))
                }.padding(24).frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
            .background(ConciergeStyle.navy)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .onAppear { if store.area == .ays { username = "ays" } }
        }
        .tint(ConciergeStyle.teal)
    }

    @MainActor private func signIn() async {
        busy = true; error = nil; defer { busy = false }
        do {
            try await store.signIn(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            password = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
