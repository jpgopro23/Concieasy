import SwiftUI

struct ContentView: View {
    @State private var request = ""

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Good morning")
                                .foregroundColor(.secondary)

                            Text("Make life feel easy.")
                                .font(.largeTitle.bold())
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Label("Ask your concierge", systemImage: "sparkles")
                                .font(.headline)

                            Text("Tell me what you need and I’ll help you figure out the next step.")
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("What can I help with?", text: $request)
                                    .textFieldStyle(.roundedBorder)

                                Button(action: {}) {
                                    Image(systemName: "arrow.up")
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.black)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.25))
                        .cornerRadius(24)

                        Text("Start with an idea")
                            .font(.headline)

                        SuggestionRow(icon: "fork.knife", title: "Find a dinner spot")
                        SuggestionRow(icon: "airplane", title: "Plan a getaway")
                        SuggestionRow(icon: "gift", title: "Pick a thoughtful gift")
                    }
                    .padding()
                }
                .navigationBarHidden(true)
            }
            .tabItem {
                Label("Home", systemImage: "sparkles")
            }

            Text("Your plans will appear here.")
                .tabItem {
                    Label("Plans", systemImage: "calendar")
                }

            Text("Saved recommendations will appear here.")
                .tabItem {
                    Label("Saved", systemImage: "bookmark")
                }
        }
        .accentColor(.black)
    }
}

struct SuggestionRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 42, height: 42)
                .background(Color.green.opacity(0.2))
                .cornerRadius(12)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(16)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
