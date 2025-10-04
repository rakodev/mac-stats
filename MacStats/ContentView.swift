import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProjectTitleLink()

            Text("This app runs in the menu bar. Look for the CPU/Memory stats in your menu bar.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(width: 400, height: 200)
    }
}

private struct ProjectTitleLink: View {
    @State private var hovering = false
    var body: some View {
        Button(action: { MenuBarController.openProjectPage() }) {
            HStack(spacing: 6) {
                Text("Mac Stats")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
                    .offset(y: 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(hovering ? Color.blue.opacity(0.12) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open project page on GitHub")
    }
}

#Preview {
    ContentView()
}