import CoreLocation
import Foundation
import MapKit
import PokiCore
import UIKit
import WeatherKit

/// Location, maps and weather. Location requests are one-shot with a timeout and cancellation; a
/// place name is geocoded once and its coordinate is passed to nearby search and routing, so a name
/// shared by two places cannot silently route somewhere else. WeatherKit's Apple Weather attribution
/// travels with every forecast answer.
enum PlaceTools {
    static let specs: [ToolSpec] = [
        .make("location_current",
              "Read this iPhone's current location once, with its accuracy and any address Core Location can reverse geocode. The owner must allow location while using Poki. A timeout, a refusal and a reduced-accuracy reading are reported separately.",
              [
                "timeout": ["type": "number", "minimum": 3, "maximum": 60],
                "address": ["type": "boolean", "description": "Reverse geocode the place (default true)."],
              ], []),
        .make("maps_geocode",
              "Turn a place name or address into coordinates. More than one matching place is reported as ambiguous with its candidates; nothing is guessed.",
              ["address": ["type": "string"]], ["address"]),
        .make("maps_search",
              "Search Apple Maps for nearby places. near, or latitude/longitude, sets the center; otherwise this iPhone's location is used. Returns names, categories, addresses and coordinates that maps_route accepts directly.",
              [
                "query": ["type": "string"],
                "near": ["type": "string"],
                "latitude": ["type": "number"],
                "longitude": ["type": "number"],
                "radius_km": ["type": "number", "minimum": 0.5, "maximum": 50],
                "limit": ["type": "integer", "minimum": 1, "maximum": 20],
              ], ["query"]),
        .make("maps_route",
              "Plan a route with Apple Maps from from to to (names, addresses or latitude,longitude). from defaults to this iPhone's location. Returns the mode, distance, travel time, estimated arrival and the main steps. A mode that cannot be planned is reported as such.",
              [
                "from": ["type": "string"],
                "from_latitude": ["type": "number"],
                "from_longitude": ["type": "number"],
                "to": ["type": "string"],
                "to_latitude": ["type": "number"],
                "to_longitude": ["type": "number"],
                "mode": ["type": "string", "enum": ["driving", "walking", "transit", "cycling"]],
              ], ["to"]),
        .make("weather_forecast",
              "Read the current weather and hourly or daily forecast from Apple Weather. Give a place name or latitude/longitude; otherwise this iPhone's location is used. Returns the place, times, units and the Apple Weather attribution required wherever the forecast is shown.",
              [
                "location": ["type": "string"],
                "latitude": ["type": "number"],
                "longitude": ["type": "number"],
                "days": ["type": "integer", "minimum": 1, "maximum": 10],
                "hours": ["type": "integer", "minimum": 0, "maximum": 24],
              ], []),
    ]

    // MARK: Current location

    @MainActor static func current(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let timeout = min(60, max(3, args.double("timeout") ?? 15))
        let result = await LocationProvider.shared.request(timeout: timeout)
        switch result {
        case .denied:
            return NativeToolAnswer.permission("location access is not allowed. Open Settings › Privacy & Security › Location Services › Poki and allow While Using. Nothing was read.")
        case .timeout:
            return NativeToolAnswer.timeout("Core Location did not answer within \(Int(timeout)) s; nothing was read.")
        case .failed(let reason):
            return NativeToolAnswer.failed("Core Location failed: \(reason)")
        case .unavailable(let reason):
            return NativeToolAnswer.unavailable(reason)
        case .location(let location):
            let accuracy = location.horizontalAccuracy >= 0 ? "\(Int(location.horizontalAccuracy.rounded())) m" : "unknown"
            var text = "location: \(String(format: "%.5f,%.5f", location.coordinate.latitude, location.coordinate.longitude))\naccuracy: \(accuracy)\nread at: \(NativeDate.display(location.timestamp)) (\(TimeZone.current.identifier))\nprecision: \(LocationProvider.shared.reducedAccuracy ? "reduced (approximate)" : "full")"
            if args.bool("address") ?? true {
                if let placemark = await reverseGeocode(location) {
                    let address = formatted(placemark)
                    if !address.isEmpty { text += "\naddress: \(address)" }
                }
            }
            return NativeToolAnswer.ok(text)
        }
    }

    // MARK: Geocode

    static func geocode(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        guard let address = args.string("address") else { return NativeToolAnswer.invalid("address is required; nothing was looked up") }
        switch await lookUp(address) {
        case .failed(let reason):
            return NativeToolAnswer.failed("Apple Maps could not look up “\(address)”: \(reason)")
        case .empty:
            return NativeToolAnswer.empty("no place matched “\(address)”.")
        case .ambiguous(let places):
            return NativeToolAnswer.ambiguous("more than one place matches “\(address)”: \(places.map(placeLine).joined(separator: " | ")). Ask the owner which one before routing or searching; nothing was chosen.")
        case .one(let place):
            return NativeToolAnswer.ok("place: \(formatted(place.placemark))\ncoordinate: \(String(format: "%.5f,%.5f", place.coordinate.latitude, place.coordinate.longitude))\n\(placeLine(place))")
        }
    }

    // MARK: Nearby places

    static func search(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        guard let query = args.string("query") else { return NativeToolAnswer.invalid("query is required; nothing was searched") }
        let center: CLLocationCoordinate2D?
        if let latitude = args.double("latitude"), let longitude = args.double("longitude"),
           (-90...90).contains(latitude), (-180...180).contains(longitude) {
            center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else if let near = args.string("near") {
            switch await lookUp(near) {
            case .one(let place): center = place.coordinate
            case .ambiguous(let places):
                return NativeToolAnswer.ambiguous("“\(near)” matches more than one place: \(places.map(placeLine).joined(separator: " | ")). Ask the owner which one; nothing was searched.")
            case .empty:
                return NativeToolAnswer.empty("no place matched “\(near)”, so nothing was searched.")
            case .failed(let reason):
                return NativeToolAnswer.failed("Apple Maps could not place “\(near)”: \(reason)")
            }
        } else {
            switch await LocationProvider.shared.request(timeout: 15) {
            case .location(let location): center = location.coordinate
            case .denied:
                return NativeToolAnswer.permission("nearby search needs this iPhone's location or a near place. Allow location for Poki, or pass near. Nothing was searched.")
            case .timeout:
                return NativeToolAnswer.timeout("location did not answer; nothing was searched.")
            case .failed(let reason):
                return NativeToolAnswer.failed("location failed: \(reason)")
            case .unavailable(let reason):
                return NativeToolAnswer.unavailable(reason)
            }
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest]
        if let center {
            let radius = min(50, max(0.5, args.double("radius_km") ?? 10)) * 1000
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        }
        do {
            let response = try await localSearch(request)
            let limit = min(20, max(1, args.int("limit") ?? 10))
            let items = response.mapItems.prefix(limit)
            guard !items.isEmpty else {
                let around = center.map { String(format: " around %.4f,%.4f", $0.latitude, $0.longitude) } ?? ""
                return NativeToolAnswer.empty("no nearby place matched “\(query)”\(around).")
            }
            let lines = items.map { item -> String in
                let coordinate = item.placemark.coordinate
                let itemName = item.name ?? "unnamed"
                let category = item.pointOfInterestCategory?.rawValue ?? "place"
                var line = "- \(itemName) — \(category) — \(String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude))"
                let address = formatted(item.placemark)
                if !address.isEmpty { line += " — \(address)" }
                if let center {
                    let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                    line += String(format: " — %.1f km from the center", distance / 1000)
                }
                return line
            }
            return NativeToolAnswer.ok("places: \(items.count)\n" + lines.joined(separator: "\n"))
        } catch {
            return NativeToolAnswer.failed("Apple Maps search failed: \(error.localizedDescription)")
        }
    }

    // MARK: Route

    static func route(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let mode: MKDirectionsTransportType
        switch (args.string("mode") ?? "driving").lowercased() {
        case "walking": mode = .walking
        case "transit": mode = .transit
        case "cycling": mode = .cycling
        default: mode = .automobile
        }
        let source: MKMapItem
        if let latitude = args.double("from_latitude"), let longitude = args.double("from_longitude") {
            source = mapItem(latitude: latitude, longitude: longitude, name: "Start")
        } else if let from = args.string("from") {
            switch await place(from) {
            case .one(let place): source = mapItem(for: place)
            case .ambiguous(let places):
                return NativeToolAnswer.ambiguous("the start “\(from)” matches more than one place: \(places.map(placeLine).joined(separator: " | ")). Ask the owner which one; nothing was routed.")
            case .empty: return NativeToolAnswer.empty("no place matched the start “\(from)”; nothing was routed.")
            case .failed(let reason): return NativeToolAnswer.failed("the start could not be placed: \(reason)")
            }
        } else {
            switch await LocationProvider.shared.request(timeout: 15) {
            case .location(let location): source = mapItem(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, name: "This iPhone")
            case .denied: return NativeToolAnswer.permission("a route from here needs this iPhone's location or a from place. Nothing was routed.")
            case .timeout: return NativeToolAnswer.timeout("location did not answer; nothing was routed.")
            case .failed(let reason): return NativeToolAnswer.failed("location failed: \(reason)")
            case .unavailable(let reason): return NativeToolAnswer.unavailable(reason)
            }
        }
        let destination: MKMapItem
        if let latitude = args.double("to_latitude"), let longitude = args.double("to_longitude") {
            destination = mapItem(latitude: latitude, longitude: longitude, name: "Destination")
        } else if let to = args.string("to") {
            switch await place(to) {
            case .one(let place): destination = mapItem(for: place)
            case .ambiguous(let places):
                return NativeToolAnswer.ambiguous("the destination “\(to)” matches more than one place: \(places.map(placeLine).joined(separator: " | ")). Ask the owner which one; nothing was routed.")
            case .empty: return NativeToolAnswer.empty("no place matched the destination “\(to)”; nothing was routed.")
            case .failed(let reason): return NativeToolAnswer.failed("the destination could not be placed: \(reason)")
            }
        } else {
            return NativeToolAnswer.invalid("to is required; nothing was routed")
        }
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = mode
        request.requestsAlternateRoutes = false
        do {
            let response = try await directions(request)
            guard let route = response.routes.first else {
                let fromName = source.name ?? "the start"
                let toName = destination.name ?? "the destination"
                return NativeToolAnswer.empty("Apple Maps found no route by \(modeName(mode)) from \(fromName) to \(toName).")
            }
            let arrival = Date().addingTimeInterval(route.expectedTravelTime)
            let distance = Measurement(value: route.distance, unit: UnitLength.meters)
            let fromName = source.name ?? "start"
            let toName = destination.name ?? "destination"
            var text = "route: \(modeName(mode)) — \(distanceText(distance))\nfrom: \(fromName)\nto: \(toName)\ntime: \(durationText(route.expectedTravelTime))\neta: \(NativeDate.display(arrival)) (\(TimeZone.current.identifier))"
            let steps = route.steps.filter { !$0.instructions.isEmpty }.prefix(8)
            if !steps.isEmpty {
                text += "\nsteps:\n" + steps.map { "- \($0.instructions) — \(distanceText(Measurement(value: $0.distance, unit: UnitLength.meters)))" }.joined(separator: "\n")
            }
            if response.routes.count > 1 { text += "\n(alternate routes were not requested)" }
            return NativeToolAnswer.ok(text)
        } catch {
            return NativeToolAnswer.failed("Apple Maps could not plan a \(modeName(mode)) route: \(error.localizedDescription). No route was made.")
        }
    }

    // MARK: Weather

    @MainActor static func weather(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let place: (CLLocation, String)
        if let latitude = args.double("latitude"), let longitude = args.double("longitude"),
           (-90...90).contains(latitude), (-180...180).contains(longitude) {
            place = (CLLocation(latitude: latitude, longitude: longitude), String(format: "%.4f,%.4f", latitude, longitude))
        } else if let name = args.string("location") {
            switch await lookUp(name) {
            case .one(let item):
                guard let location = item.placemark.location else { return NativeToolAnswer.failed("the place had no coordinate; nothing was read.") }
                place = (location, formatted(item.placemark).nilIfEmpty ?? name)
            case .ambiguous(let places):
                return NativeToolAnswer.ambiguous("“\(name)” matches more than one place: \(places.map(placeLine).joined(separator: " | ")). Ask the owner which one; nothing was read.")
            case .empty:
                return NativeToolAnswer.empty("no place matched “\(name)”; nothing was read.")
            case .failed(let reason):
                return NativeToolAnswer.failed("the place could not be found: \(reason)")
            }
        } else {
            switch await LocationProvider.shared.request(timeout: 15) {
            case .location(let location):
                place = (location, "this iPhone")
            case .denied:
                return NativeToolAnswer.permission("weather here needs this iPhone's location or a place. Allow location for Poki, or name the place. Nothing was read.")
            case .timeout:
                return NativeToolAnswer.timeout("location did not answer; nothing was read.")
            case .failed(let reason):
                return NativeToolAnswer.failed("location failed: \(reason)")
            case .unavailable(let reason):
                return NativeToolAnswer.unavailable(reason)
            }
        }
        do {
            let weather = try await WeatherService.shared.weather(for: place.0)
            let days = min(10, max(1, args.int("days") ?? 3))
            let hours = min(24, max(0, args.int("hours") ?? 0))
            var text = "weather: \(place.1)\nread at: \(NativeDate.display(Date())) (\(TimeZone.current.identifier))\nunits: \(temperatureUnitName())\n\ncurrent:\n\(currentLine(weather.currentWeather))"
            let daily = Array(weather.dailyForecast.prefix(days))
            if !daily.isEmpty {
                text += "\ndaily:\n" + daily.map(dayLine).joined(separator: "\n")
            }
            if hours > 0 {
                let hourly = Array(weather.hourlyForecast.prefix(hours))
                if !hourly.isEmpty { text += "\nhourly:\n" + hourly.map(hourLine).joined(separator: "\n") }
            }
            if let alerts = weather.weatherAlerts, !alerts.isEmpty {
                text += "\nalerts:\n" + alerts.prefix(5).map { "- \($0.summary) (\($0.severity))" }.joined(separator: "\n")
            }
            let attribution = try await WeatherService.shared.attribution
            lastWeatherCredit = WeatherCredit(service: attribution.serviceName, legal: attribution.legalPageURL,
                                              markLight: attribution.combinedMarkLightURL, markDark: attribution.combinedMarkDarkURL)
            text += "\nattribution: \(attribution.serviceName)\nlegal: \(attribution.legalPageURL.absoluteString)"
            return NativeToolAnswer.ok(text)
        } catch let error as WeatherError {
            if case .permissionDenied = error {
                return NativeToolAnswer.permission("WeatherKit is not authorized for Poki. Enable WeatherKit for the App ID and signing profile, then allow Poki's weather access. Nothing was read.")
            }
            return NativeToolAnswer.failed("Apple Weather could not answer: \(error.localizedDescription)")
        } catch {
            return NativeToolAnswer.failed("Apple Weather could not answer: \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    enum GeocodeResult {
        case one(Place)
        case ambiguous([Place])
        case empty
        case failed(String)
    }

    /// The mark and legal link Apple Weather requires beside a forecast. Kept after the call so the
    /// chat can show it under the answer.
    struct WeatherCredit: Equatable {
        var service: String
        var legal: URL
        var markLight: URL
        var markDark: URL
    }

    @MainActor static private(set) var lastWeatherCredit: WeatherCredit?

    struct Place {
        let placemark: CLPlacemark
        var coordinate: CLLocationCoordinate2D { placemark.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        var name: String { placemark.name ?? formatted(placemark) }
    }

    static func lookUp(_ address: String) async -> GeocodeResult {
        let geocoder = CLGeocoder()
        do {
            let marks = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CLPlacemark], Error>) in
                geocoder.geocodeAddressString(address) { marks, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: marks ?? []) }
                }
            }
            let places = marks.filter { $0.location != nil }.map { Place(placemark: $0) }
            if places.isEmpty { return .empty }
            // A city often yields several near-identical placemarks; keep a strictly distinct set.
            let distinct = places.reduce(into: [Place]()) { result, place in
                if !result.contains(where: { $0.coordinate.latitude == place.coordinate.latitude && $0.coordinate.longitude == place.coordinate.longitude }) { result.append(place) }
            }
            return distinct.count == 1 ? .one(distinct[0]) : .ambiguous(distinct)
        } catch {
            if (error as? CLError)?.code == .geocodeFoundNoResult { return .empty }
            return .failed(error.localizedDescription)
        }
    }

    private static func place(_ text: String) async -> GeocodeResult {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, (-90...90).contains(parts[0]), (-180...180).contains(parts[1]) {
            let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]))
            return .one(Place(placemark: CLPlacemark(placemark: placemark)))
        }
        if let coordinate = coordinate(from: text) {
            let placemark = MKPlacemark(coordinate: coordinate)
            return .one(Place(placemark: CLPlacemark(placemark: placemark)))
        }
        return await lookUp(text)
    }

    private static func coordinate(from text: String) -> CLLocationCoordinate2D? {
        let numbers = text.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Double($0) }
        guard numbers.count == 2, (-90...90).contains(numbers[0]), (-180...180).contains(numbers[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: numbers[0], longitude: numbers[1])
    }

    private static func mapItem(for place: Place) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        return item
    }

    private static func mapItem(latitude: Double, longitude: Double, name: String) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        return item
    }

    private static func localSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { continuation in
            MKLocalSearch(request: request).start { response, error in
                if let error { continuation.resume(throwing: error) } else if let response { continuation.resume(returning: response) } else { continuation.resume(throwing: NSError(domain: kCLErrorDomain, code: CLError.Code.locationUnknown.rawValue)) }
            }
        }
    }

    private static func directions(_ request: MKDirections.Request) async throws -> MKDirections.Response {
        try await withCheckedThrowingContinuation { continuation in
            MKDirections(request: request).calculate { response, error in
                if let error { continuation.resume(throwing: error) } else if let response { continuation.resume(returning: response) } else { continuation.resume(throwing: NSError(domain: MKErrorDomain, code: 3)) }
            }
        }
    }

    private static func reverseGeocode(_ location: CLLocation) async -> CLPlacemark? {
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(location)
            return marks.first
        } catch { return nil }
    }

    private static func formatted(_ placemark: CLPlacemark) -> String {
        let parts = [placemark.name, placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0?.nilIfEmpty }
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }.joined(separator: ", ")
    }

    private static func placeLine(_ place: Place) -> String {
        let coordinate = String(format: "%.5f,%.5f", place.coordinate.latitude, place.coordinate.longitude)
        return "\(formatted(place.placemark)) (\(coordinate))"
    }

    private static func modeName(_ mode: MKDirectionsTransportType) -> String {
        switch mode {
        case .walking: return "walking"
        case .transit: return "transit"
        case .cycling: return "cycling"
        default: return "driving"
        }
    }

    private static func distanceText(_ measurement: Measurement<UnitLength>) -> String {
        let kilometers = measurement.converted(to: .kilometers).value
        return kilometers < 1 ? String(format: "%.0f m", measurement.converted(to: .meters).value) : String(format: "%.1f km", kilometers)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    private static func currentLine(_ current: CurrentWeather) -> String {
        "\(current.condition.description) — \(temperature(current.temperature)), feels like \(temperature(current.apparentTemperature)) — humidity \(Int(current.humidity * 100))% — wind \(windText(current.wind)) — UV \(current.uvIndex.value)"
    }

    private static func dayLine(_ day: DayWeather) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return "- \(weekday): \(day.condition.description) — high \(temperature(day.highTemperature)), low \(temperature(day.lowTemperature)) — rain \(Int(day.precipitationChance * 100))%"
    }

    private static func hourLine(_ hour: HourWeather) -> String {
        "- \(hour.date.formatted(.dateTime.hour().minute())): \(hour.condition.description) — \(temperature(hour.temperature)) — rain \(Int(hour.precipitationChance * 100))%"
    }

    private static func temperature(_ measurement: Measurement<UnitTemperature>) -> String {
        let celsius = measurement.converted(to: .celsius).value
        let fahrenheit = celsius * 9 / 5 + 32
        return String(format: "%.0f°C (%.0f°F)", celsius, fahrenheit)
    }

    private static func windText(_ wind: Wind) -> String {
        let speed = wind.speed.converted(to: .kilometersPerHour).value
        return String(format: "%.0f km/h %@", speed, wind.compassDirection.description)
    }

    private static func temperatureUnitName() -> String { "°C, with °F beside it; wind km/h" }
}

/// One current-location request at a time, with its own timeout and cancellation. Core Location's
/// delegate is on the main queue; the continuation is resolved once.
@MainActor
private final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Result {
        case location(CLLocation)
        case denied
        case timeout
        case failed(String)
        case unavailable(String)
    }

    static let shared = LocationProvider()
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Result, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var started = Date()

    var reducedAccuracy: Bool { manager.accuracyAuthorization == .reducedAccuracy }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(timeout: TimeInterval) async -> Result {
        guard continuation == nil else { return .unavailable("another location request is already waiting; nothing new was read.") }
        guard CLLocationManager.locationServicesEnabled() else {
            return .unavailable("Location Services are off for this iPhone. Turn them on in Settings › Privacy & Security › Location Services.")
        }
        switch manager.authorizationStatus {
        case .denied:
            return .denied
        case .restricted:
            return .denied
        case .notDetermined:
            guard UIApplication.shared.applicationState == .active else {
                return .denied
            }
            manager.requestWhenInUseAuthorization()
            for _ in 0..<50 {
                guard manager.authorizationStatus == .notDetermined else { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { return .denied }
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return .unavailable("location permission state is unknown.")
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.started = Date()
                self.manager.requestLocation()
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    self?.finish(.timeout)
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failed("the request was cancelled.")) }
        }
    }

    private func finish(_ result: Result) {
        let pending = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.resume(returning: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.finish(.denied)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.finish(.location(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let code = (error as? CLError)?.code
            self.finish(code == .denied ? .denied : .failed(error.localizedDescription))
        }
    }
}
