// lib/widgets/message_route_map.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Represents a hop in the APRS route (callsign and optional lat/lon).
class RouteHop {
  final String callsign;
  final double? lat;
  final double? lon;

  RouteHop({required this.callsign, this.lat, this.lon});

  factory RouteHop.fromJson(dynamic json) {
    if (json is Map) {
      return RouteHop(
        callsign: json['callsign'] ?? '',
        lat: (json['lat'] is num) ? json['lat'].toDouble() : null,
        lon: (json['lon'] is num) ? json['lon'].toDouble() : null,
      );
    }
    // Fallback for older data format if any
    return RouteHop(callsign: json.toString());
  }
}

/// A widget that draws the APRS message route on a real OpenStreetMap view.
class MessageRouteMap extends StatelessWidget {
  final List<RouteHop> route;
  final String contact;

  const MessageRouteMap({
    super.key,
    required this.route,
    required this.contact,
    bool horizontal = false, // Kept for compatibility, but no longer used.
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Filter for hops that have actual coordinate data.
    final List<RouteHop> locatedHops =
        route.where((hop) => hop.lat != null && hop.lon != null).toList();
    final List<LatLng> points =
        locatedHops.map((hop) => LatLng(hop.lat!, hop.lon!)).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The actual map widget
          FlutterMap(
            options: MapOptions(
              initialCenter: points.isNotEmpty
                  ? LatLngBounds.fromPoints(points).center
                  : const LatLng(30, 0), // Default world view
              initialZoom: points.isNotEmpty ? 4.0 : 1.0,
              bounds:
                  points.isNotEmpty ? LatLngBounds.fromPoints(points) : null,
              boundsOptions: const FitBoundsOptions(padding: EdgeInsets.all(40.0)),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'dev.k8sdr.aprs_messenger',
              ),
              // Only draw polylines if there are at least 2 points with coordinates
              if (points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                        points: points, strokeWidth: 4.5, color: Colors.blue.withOpacity(0.8)),
                  ],
                ),
              // Only draw markers if there are points with coordinates
              if (points.isNotEmpty)
                MarkerLayer(
                  markers: locatedHops.map((hop) {
                    final isEndpoint = hop.callsign == route.first.callsign ||
                        hop.callsign == route.last.callsign;
                    return Marker(
                      width: 80.0,
                      height: 50.0,
                      point: LatLng(hop.lat!, hop.lon!),
                      child: Tooltip(
                        message: hop.callsign,
                        child: Icon(
                          Icons.location_on,
                          color: isEndpoint
                              ? theme.colorScheme.primary
                              : Colors.orange.shade800,
                          size: 35.0,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 5)],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),

          // This is the fallback text overlay for routes without any coordinate data.
          if (points.isEmpty && route.isNotEmpty)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 2)],
                  ),
                  child: Text(
                    route.map((hop) => hop.callsign).join(' → '),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),

          // Title Overlay
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Message Route: $contact",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}