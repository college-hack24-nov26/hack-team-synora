import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:medicoscope/models/ambulance_booking_model.dart';
import 'package:medicoscope/services/ambulance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AmbulanceBooking Model Tests', () {
    test('AmbulanceBooking serialization round-trip', () {
      final now = DateTime.now();
      final original = AmbulanceBooking(
        bookingId: 'AMB-TEST-001',
        patientId: 'patient_123',
        patientName: 'John Doe',
        hospitalName: 'Apollo Emergency Center',
        hospitalLatitude: 28.6139,
        hospitalLongitude: 77.2090,
        patientLatitude: 28.6250,
        patientLongitude: 77.2150,
        paramedicName: 'Paramedic Team Alpha',
        driverPhone: '108',
        vehicleNumber: 'MED-ALS-999',
        initialEtaMinutes: 6,
        status: 'dispatched',
        criticalAlert: 'Cardiac Arrhythmia Critical',
        dispatchedAt: now,
      );

      final json = original.toJson();
      final parsed = AmbulanceBooking.fromJson(json);

      expect(parsed.bookingId, equals('AMB-TEST-001'));
      expect(parsed.hospitalName, equals('Apollo Emergency Center'));
      expect(parsed.paramedicName, equals('Paramedic Team Alpha'));
      expect(parsed.driverPhone, equals('108'));
      expect(parsed.vehicleNumber, equals('MED-ALS-999'));
      expect(parsed.initialEtaMinutes, equals(6));
      expect(parsed.status, equals('dispatched'));
      expect(parsed.criticalAlert, equals('Cardiac Arrhythmia Critical'));
      expect(parsed.hospitalLatitude, closeTo(28.6139, 0.0001));
      expect(parsed.hospitalLongitude, closeTo(77.2090, 0.0001));
      expect(parsed.patientLatitude, closeTo(28.6250, 0.0001));
      expect(parsed.patientLongitude, closeTo(77.2150, 0.0001));
    });

    test('AmbulanceBooking factory defaults', () {
      final parsed = AmbulanceBooking.fromJson({});
      expect(parsed.bookingId, isNotEmpty);
      expect(parsed.driverPhone, equals('108'));
      expect(parsed.status, equals('dispatched'));
      expect(parsed.initialEtaMinutes, equals(8));
    });
  });

  group('AmbulanceService Route Generation Tests', () {
    test('generateRouteCoordinates creates valid, non-empty waypoints from start to end', () {
      const hospitalLoc = LatLng(28.6139, 77.2090);
      const patientLoc = LatLng(28.6300, 77.2250);

      final route = AmbulanceService.generateRouteCoordinates(
        start: hospitalLoc,
        end: patientLoc,
        steps: 25,
      );

      expect(route.length, equals(26));
      expect(route.first.latitude, equals(hospitalLoc.latitude));
      expect(route.first.longitude, equals(hospitalLoc.longitude));
      expect(route.last.latitude, equals(patientLoc.latitude));
      expect(route.last.longitude, equals(patientLoc.longitude));

      // Verify all intermediate coordinates are valid numbers and monotonically move toward end
      for (final pt in route) {
        expect(pt.latitude.isNaN, isFalse);
        expect(pt.longitude.isNaN, isFalse);
        expect(pt.latitude, inInclusiveRange(28.60, 28.65));
        expect(pt.longitude, inInclusiveRange(77.20, 77.24));
      }
    });
  });
}

