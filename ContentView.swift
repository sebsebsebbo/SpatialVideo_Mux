import SwiftUI

// A minimal starter UI so the app launches and shows something real.
// It lets you pick between the export formats defined in ExportFormat.swift
// and displays that format's description. Replace/expand this as you paste
// in your full UI code.
struct ContentView: View {
    @State private var selectedFormat: ExportFormat = .hsbs

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SpatialVideo Mux")
                .font(.largeTitle)
                .bold()

            Picker("Export Format", selection: $selectedFormat) {
                ForEach(ExportFormat.releaseCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedFormat.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Per-eye width: \(selectedFormat.eyeWidth) px")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(30)
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
