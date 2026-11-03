import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:medicoscope/models/ambulance_booking_model.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/services/location_service.dart';
import 'package:medicoscope/services/overpass_hospitals_service.dart';
import 'package:medicoscope/widgets/critical_alert_countdown_dialog.dart';
import 'package:medicoscope/screens/ambulance/ambulance_tracking_screen.dart';

class AmbulanceService {
  static AmbulanceBooking? _currentActiveBooking;
  static bool _isCountdownShowing = false;

  static AmbulanceBooking? get currentBooking => _currentActiveBooking;

  /// Trigger the countdown popup for any critical alert across the app.
  static void triggerCriticalAlertCountdown({
    required BuildContext context,
    required String alertHeadline,
    required String alertSeverity,
    required String patientName,
    String? patientId,
    String? details,
    int countdownSeconds = 5,
  }) {
    if (_isCountdownShowing) return;
    _isCountdownShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CriticalAlertCountdownDialog(
        alertHeadline: alertHeadline,
        alertSeverity: alertSeverity,
        patientName: patientName,
        countdownSeconds: countdownSeconds,
        onConfirmed: () async {
          _isCountdownShowing = false;
          Navigator.of(ctx).pop();
          // Book ambulance and navigate to tracking simulation
          final booking = await bookEmergencyAmbulance(
            patientName: patientName,
            patientId: patientId ?? 'anonymous',
            criticalAlert: '$alertHeadline ${details ?? ''}',
          );
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AmbulanceTrackingScreen(booking: booking),
              ),
            );
          }
        },
        onCancelled: () {
          _isCountdownShowing = false;
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ambulance auto-booking cancelled by user.'),
              backgroundColor: Colors.blueGrey,
            ),
          );
        },
      ),
    ).then((_) => _isCountdownShowing = false);
  }

  /// Finds the closest medical facility and creates an active ambulance booking.
  static Future<AmbulanceBooking> bookEmergencyAmbulance({
    required String patientName,
    required String patientId,
    required String criticalAlert,
  }) async {
    final fix = await LocationService.getFix();
    final patientLat = fix.latitude ?? 28.6139; // Default fallback to city coordinates if GPS disabled
    final patientLng = fix.longitude ?? 77.2090;

    String hospitalName = 'City Emergency Trauma Center';
    double hospLat = patientLat + 0.018; // ~2km offset
    double hospLng = patientLng + 0.015;
    int etaMinutes = 7;

    try {
      final hospitals = await OverpassHospitalsService.fetchNearby(
        center: LatLng(patientLat, patientLng),
        radiusMeters: 5000,
      ).timeout(const Duration(seconds: 4), onTimeout: () => []);

      if (hospitals.isNotEmpty) {
        final nearest = hospitals.first;
        hospitalName = nearest.name;
        hospLat = nearest.location.latitude;
        hospLng = nearest.location.longitude;
        final distKm = nearest.distanceMeters / 1000.0;
        etaMinutes = math.max(3, (distKm * 2.5).round());
      }
    } catch (_) {}

    final bookingPayload = {
      'bookingId': 'AMB-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      'patientId': patientId,
      'patientName': patientName,
      'hospitalName': hospitalName,
      'hospitalLocation': {
        'latitude': hospLat,
        'longitude': hospLng,
      },
      'patientLocation': {
        'latitude': patientLat,
        'longitude': patientLng,
      },
      'paramedicName': 'Dr. Sharma & ALS ICU Paramedic Crew',
      'driverPhone': '108',
      'vehicleNumber': 'MED-ALS-${(100 + math.Random().nextInt(899))}',
      'etaMinutes': etaMinutes,
      'status': 'dispatched',
      'criticalAlert': criticalAlert,
      'dispatchedAt': DateTime.now().toIso8601String(),
    };

    final booking = AmbulanceBooking.fromJson(bookingPayload);
    _currentActiveBooking = booking;

    // Post to backend (best-effort)
    try {
      final api = ApiService();
      await api.post('/ambulance/book', bookingPayload);
    } catch (_) {}

    return booking;
  }

  /// Interpolates a smooth route polyline with simulated turns from hospital to user coordinates.
  static List<LatLng> generateRouteCoordinates({
    required LatLng start,
    required LatLng end,
    int steps = 30,
  }) {
    final points = <LatLng>[start];
    final random = math.Random(42); // deterministic seed for smooth curve

    final dLat = (end.latitude - start.latitude) / steps;
    final dLng = (end.longitude - start.longitude) / steps;

    for (int i = 1; i < steps; i++) {
      // Add slight road-like jitter
      final jitterLat = (random.nextDouble() - 0.5) * 0.001;
      final jitterLng = (random.nextDouble() - 0.5) * 0.001;
      points.add(
        LatLng(
          start.latitude + (dLat * i) + jitterLat,
          start.longitude + (dLng * i) + jitterLng,
        ),
      );
    }

    points.add(end);
    return points;
  }
}
