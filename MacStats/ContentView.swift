import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Mac Stats")
                .font(.largeTitle)
                .padding()
            
            Text("This app runs in the menu bar. Look for the CPU/Memory stats in your menu bar.")
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(width: 400, height: 200)
    }
}

#Preview {
    ContentView()
}