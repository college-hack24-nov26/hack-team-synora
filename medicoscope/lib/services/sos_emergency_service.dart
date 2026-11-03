import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/services/location_service.dart';

/// Represents a patient's configured SOS emergency contact.
class SosContact {
  final String name;
  final String phone;
  final String relationship;

  const SosContact({
    this.name = '',
    this.phone = '',
    this.relationship = '',
  });

  bool get isValid => phone.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'phone': phone.trim(),
        'relationship': relationship.trim(),
      };

  factory SosContact.fromJson(Map<String, dynamic> json) => SosContact(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        relationship: json['relationship'] as String? ?? '',
      );

  static const empty = SosContact();
}

/// Central service for managing the patient's SOS emergency contact and
/// dispatching emergency SMS notifications with live GPS location during alerts.
class SosEmergencyService {
  static const MethodChannel _nativeSmsChannel = MethodChannel('medicoscope/native_sms');
  static const _keySosName = 'sos_emergency_name';
  static const _keySosPhone = 'sos_emergency_phone';
  static const _keySosRelation = 'sos_emergency_relation';

  // In-memory cache for fast, synchronous access in alert hooks
  static SosContact? _cachedContact;

  // Rate-limiting / de-duplication state
  static final Map<String, DateTime> _lastSentByType = {};
  static const Duration _coolDownPeriod = Duration(seconds: 45);

  /// Load the SOS emergency contact from local SharedPreferences.
  static Future<SosContact> getContact() async {
    if (_cachedContact != null && _cachedContact!.isValid) {
      return _cachedContact!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString(_keySosPhone) ?? '';
      final name = prefs.getString(_keySosName) ?? '';
      final relation = prefs.getString(_keySosRelation) ?? '';

      final contact = SosContact(
        name: name,
        phone: phone,
        relationship: relation,
      );

      _cachedContact = contact;
      return contact;
    } catch (e) {
      debugPrint('[SosEmergencyService] Error reading local contact: $e');
      return _cachedContact ?? SosContact.empty;
    }
  }

  /// Save or update the SOS contact locally in SharedPreferences and optionally sync to backend.
  static Future<void> saveContact({
    required String name,
    required String phone,
    String relationship = '',
    String? authToken,
  }) async {
    final contact = SosContact(
      name: name.trim(),
      phone: phone.trim(),
      relationship: relationship.trim(),
    );

    _cachedContact = contact;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySosName, contact.name);
      await prefs.setString(_keySosPhone, contact.phone);
      await prefs.setString(_keySosRelation, contact.relationship);
    } catch (e) {
      debugPrint('[SosEmergencyService] Error persisting local contact: $e');
    }

    // Sync to backend if auth token is available
    if (authToken != null && authToken.isNotEmpty) {
      try {
        final api = ApiService(token: authToken);
        await api.put(ApiConstants.profile, {
          'emergencyContact': contact.toJson(),
        });
      } catch (e) {
        debugPrint('[SosEmergencyService] Error syncing contact to backend: $e');
      }
    }
  }

  /// Sync local contact from a fetched patient profile map.
  static Future<void> syncFromProfile(Map<String, dynamic>? profileMap) async {
    if (profileMap == null) return;
    final emergency = profileMap['emergencyContact'] as Map<String, dynamic>?;
    if (emergency == null) return;

    final name = (emergency['name'] as String?)?.trim() ?? '';
    final phone = (emergency['phone'] as String?)?.trim() ?? '';
    final relation = (emergency['relationship'] as String?)?.trim() ?? '';

    if (phone.isNotEmpty) {
      await saveContact(name: name, phone: phone, relationship: relation);
    }
  }

  /// Dispatches an emergency SMS to the SOS contact with live GPS location.
  ///
  /// [alertType]: unique key for de-duplicating rapid alerts (e.g. 'cardio_risk', 'bp_high')
  /// [patientName]: the patient's display name
  /// [severity]: 'CRITICAL' | 'HIGH' | 'WARNING'
  /// [headline]: brief alert title
  /// [details]: detailed finding or recommended action
  /// [locationFix]: optional pre-resolved location; if omitted, [LocationService.getFix()] is queried.
  static Future<bool> sendAlertSms({
    required String alertType,
    required String patientName,
    required String severity,
    required String headline,
    String details = '',
    LocationFix? locationFix,
  }) async {
    // 1. Verify cooldown
    final now = DateTime.now();
    if (_lastSentByType.containsKey(alertType)) {
      final last = _lastSentByType[alertType]!;
      if (now.difference(last) < _coolDownPeriod) {
        debugPrint('[SosEmergencyService] Alert SMS for $alertType suppressed by cooldown.');
        return false;
      }
    }

    // 2. Resolve contact
    final contact = await getContact();
    if (!contact.isValid) {
      debugPrint('[SosEmergencyService] No valid SOS emergency phone configured.');
      return false;
    }

    // 3. Resolve live GPS location
    final fix = locationFix ?? await LocationService.getFix();
    final locationText = fix.label.isNotEmpty ? fix.label : 'Location unavailable';
    final mapLink = fix.mapsUrl.isNotEmpty
        ? fix.mapsUrl
        : (fix.hasFix
            ? 'https://www.google.com/maps?q=${fix.latitude},${fix.longitude}'
            : 'Not available');

    // 4. Construct SMS message body
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.day}/${now.month}/${now.year}';
    final buffer = StringBuffer();
    buffer.writeln('EMERGENCY SOS ALERT - MedicoScope');
    buffer.writeln('Patient: $patientName');
    buffer.writeln('Severity: ${severity.toUpperCase()}');
    buffer.writeln('Alert: $headline');
    if (details.trim().isNotEmpty) {
      buffer.writeln('Details: ${details.trim()}');
    }
    buffer.writeln('Time: $timeStr');
    buffer.writeln('Location: $locationText');
    buffer.writeln('Live Map: $mapLink');

        final rawMessage = buffer.toString();
    final cleanPhone = contact.phone.replaceAll(RegExp(r'[^0-9+]'), '');

    // 5. Ensure SMS permission is granted if running on mobile
    try {
      if (await Permission.sms.isDenied) {
        await Permission.sms.request();
      }
    } catch (_) {}

    // 6. Attempt silent background direct SMS via native Android platform channel (no user click needed)
    bool sentDirectly = false;
    try {
      final directResult = await _nativeSmsChannel.invokeMethod<bool>('sendDirectSms', {
        'phone': cleanPhone,
        'message': rawMessage,
      });
      if (directResult == true) {
        sentDirectly = true;
        _lastSentByType[alertType] = now;
        debugPrint('[SosEmergencyService] Direct background SMS sent via SmsManager to $cleanPhone');
      }
    } catch (e) {
      debugPrint('[SosEmergencyService] Native direct SMS channel bypassed or unavailable: $e');
    }

    // 7. Parallel background dispatch to backend SMS logging & emergency gateway
    bool sentViaBackend = false;
    try {
      final api = ApiService();
      final res = await api.post('/alerts/dispatch-sms', {
        'phone': cleanPhone,
        'patientName': patientName,
        'severity': severity,
        'headline': headline,
        'message': rawMessage,
        'location': fix.toJson(),
      });
      if (res['success'] == true) {
        sentViaBackend = true;
        _lastSentByType[alertType] = now;
      }
    } catch (_) {}

    // Zero-click guarantee: never launch external SMS composer app that forces
    // the user to manually click the "Send" button.
    return sentDirectly || sentViaBackend;
  }

  /// Sends a test SOS SMS to verify the configured phone number and live GPS link.
  static Future<bool> sendTestSms({
    required String patientName,
  }) async {
    return sendAlertSms(
      alertType: 'test_sos_${DateTime.now().millisecondsSinceEpoch}',
      patientName: patientName,
      severity: 'TEST SOS',
      headline: 'Verification of MedicoScope Emergency Contact',
      details: 'This is a test notification confirming your emergency contact receives live GPS alerts.',
    );
  }
}
