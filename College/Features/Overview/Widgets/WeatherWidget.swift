// WeatherWidget.swift
// Feature: Overview
// Purpose: Overview module — WeatherWidget.
// Data: CollegePersistence / repositories when applicable.

//
//  WeatherWidget.swift
//  College
//
//  Live weather card widget using WeatherService + CoreLocation.
//

import SwiftUI
import CoreLocation

struct WeatherWidget: View {
    @Environment(AppContainer.self) private var container
    private var locationPermissionService: LocationPermissionService { container.locationPermissionService }
    @EnvironmentObject var weatherService: WeatherService
    var locationService: LocationPermissionService { container.locationPermissionService }
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "60A5FA"), Color(hex: "3B82F6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 120, height: 120)
                .blur(radius: 20)
                .offset(x: 50, y: -40)
            Circle()
                .fill(Color(hex: "93C5FD").opacity(0.2))
                .frame(width: 80, height: 80)
                .blur(radius: 16)
                .offset(x: -40, y: 60)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weatherService.isLoading ? "Fetching…" :
                             (weatherService.weather.locationName.isEmpty ? "My Location" : weatherService.weather.locationName))
                            .font(.system(size: 17, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                        Text(weatherService.weather.condition.isEmpty ? "—" : weatherService.weather.condition)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                    Spacer()
                    if weatherService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: weatherService.weather.sfSymbol)
                            .font(.system(size: 30))
                            .symbolRenderingMode(.multicolor)
                            .shadow(radius: 4)
                    }
                }

                Spacer().frame(height: 14)
                HStack(alignment: .top, spacing: 2) {
                    Text(weatherService.isLoading ? "--" : "\(weatherService.weather.temperature)")
                        .font(.system(size: 48, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                    Text("°")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.white)
                        .offset(y: 6)
                }

                HStack(spacing: 14) {
                    Label("\(weatherService.weather.humidity)%",
                          systemImage: "drop.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                    Label("\(weatherService.weather.windSpeed)mph",
                          systemImage: "wind")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                }
                .padding(.top, 6)

                Spacer(minLength: 16)

                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.bottom, 12)

                if weatherService.weather.hourlyForecast.isEmpty {
                    HStack {
                        ForEach(0..<4, id: \.self) { _ in
                            Spacer()
                            VStack(spacing: 4) {
                                Text("—")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Image(systemName: "cloud")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                Text("—°")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                    }
                } else {
                    HStack {
                        ForEach(weatherService.weather.hourlyForecast) { item in
                            Spacer()
                            VStack(spacing: 4) {
                                Text(item.hourLabel)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Image(systemName: item.sfSymbol)
                                    .font(.system(size: 12))
                                    .symbolRenderingMode(.multicolor)
                                Text("\(item.temperature)°")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color(hex: "3B82F6").opacity(0.25), radius: 16, x: 0, y: 8)
        .onChange(of: locationService.status) { _, newStatus in
            if newStatus == .authorized { locationService.requestOneShotLocation() }
        }
        .onChange(of: locationService.lastLocation) { _, loc in
            guard let loc else { return }
            Task { await weatherService.fetch(latitude: loc.coordinate.latitude,
                                              longitude: loc.coordinate.longitude) }
        }
        .onAppear {
            locationService.requestWhenInUseAuthorizationIfNeeded()
            if let loc = locationService.lastLocation {
                Task { await weatherService.fetch(latitude: loc.coordinate.latitude,
                                                  longitude: loc.coordinate.longitude) }
            }
        }
    }

    // MARK: - Descriptor

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id:           "weather",
            displayName:  "Weather",
            description:  "Live local weather, temperature and 4-hour forecast.",
            category:     .information,
            iconName:     "cloud.sun.fill",
            accentColor:  Color(hex: "3B82F6"),
            defaultHeight: 210,
            minHeight:    180,
            makePreview: {
                WeatherWidgetPreview()
            }
        )
    }
}

// MARK: - Static preview (mock data, no services)

private struct WeatherWidgetPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "60A5FA"), Color(hex: "3B82F6")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Buffalo, NY")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                        Text("Partly Cloudy")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.multicolor)
                }
                Spacer().frame(height: 10)
                HStack(alignment: .top, spacing: 2) {
                    Text("52")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                    Text("°")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .offset(y: 4)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
