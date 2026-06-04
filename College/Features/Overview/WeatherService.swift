// WeatherService.swift
// Feature: Overview
// Purpose: Overview module — WeatherData.
// Data: CollegePersistence / repositories when applicable.

//
//  WeatherService.swift
//  College
//
//  Weather data from Open-Meteo (free, no API key required).
//

import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Models

struct WeatherData {
    var locationName: String = ""
    var temperature: Int = 0
    var condition: String = ""
    var sfSymbol: String = "cloud"
    var humidity: Int = 0
    var windSpeed: Int = 0
    var hourlyForecast: [HourlyWeatherItem] = []
}

struct HourlyWeatherItem: Identifiable {
    let id = UUID()
    var hourLabel: String
    var sfSymbol: String
    var temperature: Int
}

// MARK: - Service

@MainActor
final class WeatherService: ObservableObject {
    @Published var weather: WeatherData = WeatherData()
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private var lastFetchLatitude: Double? = nil
    private var lastFetchLongitude: Double? = nil

    func fetch(latitude: Double, longitude: Double) async {
        // Debounce – skip if already fetched for same location
        if lastFetchLatitude == latitude && lastFetchLongitude == longitude { return }

        isLoading = true
        error = nil

        // Build URL
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            error = "Unable to build weather URL."
            isLoading = false
            return
        }
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "wind_speed_unit", value: "mph"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else {
            isLoading = false; return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

            // Reverse-geocode city name
            let cityName = await reverseGeocode(latitude: latitude, longitude: longitude)

            // Build hourly forecast: pick the next 4 hours from now
            let hourlyItems = buildHourlyForecast(from: decoded)

            let current = decoded.current
            var w = WeatherData()
            w.locationName = cityName
            w.temperature = Int(current.temperature_2m.rounded())
            w.condition = wmoDescription(current.weather_code)
            w.sfSymbol = wmoSFSymbol(current.weather_code)
            w.humidity = Int(current.relative_humidity_2m)
            w.windSpeed = Int(current.wind_speed_10m.rounded())
            w.hourlyForecast = hourlyItems

            weather = w
            lastFetchLatitude = latitude
            lastFetchLongitude = longitude
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Reverse Geocode

    private func reverseGeocode(latitude: Double, longitude: Double) async -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return "My Location"
        }
        let items = try? await request.mapItems
        let representations = items?.first?.addressRepresentations
        return representations?.cityName
            ?? representations?.regionName
            ?? "My Location"
    }

    // MARK: - Hourly Forecast

    private func buildHourlyForecast(from response: OpenMeteoResponse) -> [HourlyWeatherItem] {
        let hourly = response.hourly
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                                   .withColonSeparatorInTime, .withColonSeparatorInTimeZone]
        // Also try without timezone suffix
        let formatterNoTz = ISO8601DateFormatter()
        formatterNoTz.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                                       .withColonSeparatorInTime]

        var items: [HourlyWeatherItem] = []
        for i in 0..<min(hourly.time.count, hourly.temperature_2m.count) {
            let timeString = hourly.time[i]
            // try parsing with and without timezone
            let date = formatter.date(from: timeString + ":00") 
                    ?? formatter.date(from: timeString)
                    ?? formatterNoTz.date(from: timeString)
            guard let date = date, date > now else { continue }
            guard items.count < 4 else { break }

            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "h a"
            let label = hourFormatter.string(from: date)

            items.append(HourlyWeatherItem(
                hourLabel: label,
                sfSymbol: wmoSFSymbol(hourly.weather_code[i]),
                temperature: Int(hourly.temperature_2m[i].rounded())
            ))
        }

        // Fallback: take first 4 if no future ones found
        if items.isEmpty {
            for i in 0..<min(4, hourly.time.count) {
                let hourFormatter = DateFormatter()
                hourFormatter.dateFormat = "h a"
                let label = String(i + 1) + " PM"
                items.append(HourlyWeatherItem(
                    hourLabel: label,
                    sfSymbol: wmoSFSymbol(hourly.weather_code[safe: i] ?? 0),
                    temperature: Int((hourly.temperature_2m[safe: i] ?? 70).rounded())
                ))
            }
        }
        return items
    }

    // MARK: - WMO Code Mapping

    func wmoDescription(_ code: Int) -> String {
        switch code {
        case 0:           return "Clear Sky"
        case 1:           return "Mainly Clear"
        case 2:           return "Partly Cloudy"
        case 3:           return "Overcast"
        case 45, 48:      return "Foggy"
        case 51, 53, 55:  return "Drizzle"
        case 61, 63, 65:  return "Rain"
        case 71, 73, 75:  return "Snow"
        case 77:          return "Snow Grains"
        case 80, 81, 82:  return "Rain Showers"
        case 85, 86:      return "Snow Showers"
        case 95:          return "Thunderstorm"
        case 96, 99:      return "Thunderstorm w/ Hail"
        default:          return "Unknown"
        }
    }

    func wmoSFSymbol(_ code: Int) -> String {
        switch code {
        case 0:           return "sun.max.fill"
        case 1:           return "sun.max.fill"
        case 2:           return "cloud.sun.fill"
        case 3:           return "cloud.fill"
        case 45, 48:      return "cloud.fog.fill"
        case 51, 53, 55:  return "cloud.drizzle.fill"
        case 61, 63, 65:  return "cloud.rain.fill"
        case 71, 73, 75:  return "cloud.snow.fill"
        case 77:          return "cloud.snow.fill"
        case 80, 81, 82:  return "cloud.heavyrain.fill"
        case 85, 86:      return "cloud.snow.fill"
        case 95:          return "cloud.bolt.fill"
        case 96, 99:      return "cloud.bolt.rain.fill"
        default:          return "cloud.fill"
        }
    }
}

// MARK: - API Response Models

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    let hourly: HourlyWeather

    struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let relative_humidity_2m: Double
    }

    struct HourlyWeather: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
    }
}

// MARK: - Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
