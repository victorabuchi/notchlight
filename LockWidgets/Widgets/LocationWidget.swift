import MapKit
import SwiftUI

/// A map of where you are, like the iPhone's Maps widget. It uses the same place as Weather: your city if
/// you set one, otherwise the Mac's location.
struct LocationWidget: View {
    let instance: WidgetInstance
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var maps = MapSnapshots.shared

    var body: some View {
        WidgetCard(size: instance.size, padding: 0) {
            if let report = weather.report {
                ZStack(alignment: .bottomLeading) {
                    if let image = maps.image(latitude: report.latitude, longitude: report.longitude, size: instance.size, style: instance.style) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.08)
                    }
                    Circle()
                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Label(report.place, systemImage: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.12))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.frost(.regularMaterial, offscreen: .white.opacity(0.82)), in: Capsule())
                        .environment(\.colorScheme, .light)
                        .padding(12)
                }
            } else {
                WidgetPlaceholder(symbol: "location", message: weather.problem ?? "Finding where you are…")
                    .padding(16)
            }
        }
    }
}

/// Map images for the Location widget, drawn by MapKit and kept until you move.
final class MapSnapshots: ObservableObject {
    static let shared = MapSnapshots()

    @Published private var images: [String: NSImage] = [:]
    private var pending: Set<String> = []

    /// The map in a style: "map" for Apple Maps' own look, "satellite" for photos from above, "hybrid" for
    /// those photos with roads and place names.
    func image(latitude: Double, longitude: Double, size: WidgetSize, style: String) -> NSImage? {
        // Rounded, so small changes in location don't redraw the map.
        let key = String(format: "%.3f,%.3f,%@,%@", latitude, longitude, size.rawValue, style)
        if let image = images[key] { return image }
        if !pending.contains(key) {
            pending.insert(key)
            DispatchQueue.main.async { self.draw(key: key, latitude: latitude, longitude: longitude, size: size, style: style) }
        }
        return nil
    }

    private func draw(key: String, latitude: Double, longitude: Double, size: WidgetSize, style: String) {
        let points = size.points
        let options = MKMapSnapshotter.Options()
        let meters = 2400.0
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: meters,
            longitudinalMeters: meters * points.width / points.height
        )
        options.size = points
        options.mapType = switch style {
        case "satellite": .satellite
        case "hybrid": .hybrid
        default: .standard
        }
        options.pointOfInterestFilter = .excludingAll
        MKMapSnapshotter(options: options).start { [weak self] snapshot, _ in
            guard let self else { return }
            pending.remove(key)
            if let snapshot { images[key] = snapshot.image }
        }
    }
}
