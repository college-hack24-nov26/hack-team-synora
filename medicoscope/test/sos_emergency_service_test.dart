import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medicoscope/services/sos_emergency_service.dart';
import 'package:medicoscope/services/location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SosContact Unit Tests', () {
    test('SosContact.empty is invalid', () {
      const contact = SosContact.empty;
      expect(contact.isValid, isFalse);
      expect(contact.name, isEmpty);
      expect(contact.phone, isEmpty);
      expect(contact.relationship, isEmpty);
    });

    test('SosContact with phone number is valid', () {
      const contact = SosContact(
        name: 'Jane Doe',
        phone: '+15551234567',
        relationship: 'Spouse',
      );
      expect(contact.isValid, isTrue);
      expect(contact.name, equals('Jane Doe'));
      expect(contact.phone, equals('+15551234567'));
      expect(contact.relationship, equals('Spouse'));
    });

    test('SosContact JSON round-trip serialization', () {
      const original = SosContact(
        name: 'Dr. John Smith',
        phone: '9876543210',
        relationship: 'Family Physician',
      );
      final json = original.toJson();
      final parsed = SosContact.fromJson(json);

      expect(parsed.name, equals(original.name));
      expect(parsed.phone, equals(original.phone));
      expect(parsed.relationship, equals(original.relationship));
      expect(parsed.isValid, isTrue);
    });
  });

  group('SosEmergencyService Persistence & Sync Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getContact returns empty when uninitialized', () async {
      SharedPreferences.setMockInitialValues({});
      final contact = await SosEmergencyService.getContact();
      // If nothing saved in mock prefs
      expect(contact.phone, isEmpty);
    });

    test('saveContact persists to SharedPreferences and updates cache', () async {
      SharedPreferences.setMockInitialValues({});

      await SosEmergencyService.saveContact(
        name: 'Emergency Guardian',
        phone: '+919876543210',
        relationship: 'Parent',
      );

      final loaded = await SosEmergencyService.getContact();
      expect(loaded.isValid, isTrue);
      expect(loaded.name, equals('Emergency Guardian'));
      expect(loaded.phone, equals('+919876543210'));
      expect(loaded.relationship, equals('Parent'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sos_emergency_name'), equals('Emergency Guardian'));
      expect(prefs.getString('sos_emergency_phone'), equals('+919876543210'));
      expect(prefs.getString('sos_emergency_relation'), equals('Parent'));
    });

    test('syncFromProfile extracts and persists emergency contact map', () async {
      SharedPreferences.setMockInitialValues({});

      final profileMap = {
        'emergencyContact': {
          'name': 'Alex Johnson',
          'phone': '+447911123456',
          'relationship': 'Sibling',
        }
      };

      await SosEmergencyService.syncFromProfile(profileMap);

      final loaded = await SosEmergencyService.getContact();
      expect(loaded.isValid, isTrue);
      expect(loaded.name, equals('Alex Johnson'));
      expect(loaded.phone, equals('+447911123456'));
      expect(loaded.relationship, equals('Sibling'));
    });
  });

  group('LocationFix & Alert Formatting Tests', () {
    test('LocationFix formats mapsUrl correctly', () {
      const fix = LocationFix(
        latitude: 37.7749,
        longitude: -122.4194,
        label: 'San Francisco, CA',
        mapsUrl: 'https://www.google.com/maps?q=37.7749,-122.4194',
      );

      expect(fix.hasFix, isTrue);
      expect(fix.mapsUrl, contains('37.7749,-122.4194'));
      expect(fix.toJson()['locationLabel'], equals('San Francisco, CA'));
    });

    test('sendAlertSms dispatches via native SmsManager MethodChannel silently', () async {
      await SosEmergencyService.saveContact(
        name: 'Emergency Contact',
        phone: '+15559876543',
      );

      bool channelInvoked = false;
      String? invokedPhone;
      String? invokedMessage;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('medicoscope/native_sms'),
        (call) async {
          if (call.method == 'sendDirectSms') {
            channelInvoked = true;
            final args = call.arguments as Map?;
            invokedPhone = args?['phone'] as String?;
            invokedMessage = args?['message'] as String?;
            return true;
          }
          return null;
        },
      );

      final success = await SosEmergencyService.sendAlertSms(
        alertType: 'test_silent_background_modality',
        patientName: 'Test Patient',
        severity: 'CRITICAL',
        headline: 'Test Modality Breach',
        details: 'Anemia Hb < 8 g/dL detected',
        locationFix: const LocationFix(
          latitude: 12.9716,
          longitude: 77.5946,
          label: 'Bengaluru, India',
          mapsUrl: 'https://www.google.com/maps?q=12.9716,77.5946',
        ),
      );

      expect(channelInvoked, isTrue);
      expect(invokedPhone, equals('+15559876543'));
      expect(invokedMessage, contains('Test Patient'));
      expect(invokedMessage, contains('CRITICAL'));
      expect(invokedMessage, contains('https://www.google.com/maps?q=12.9716,77.5946'));
      expect(success, isTrue);
    });
  });
}

