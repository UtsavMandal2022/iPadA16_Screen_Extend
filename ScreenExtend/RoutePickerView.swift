import SwiftUI
import AVKit

/// The system audio output chooser (iPad speakers, headphones, HDMI, AirPlay).
struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor.label
        picker.activeTintColor = UIColor.tintColor
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
