import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medicoscope/core/constants/api_constants.dart';

/// A booked appointment request. Stored locally so the patient sees their
/// upcoming appointments even if the backend hasn't acknowledged yet.
class Appointment {
  final String id;
  final String doctorId;
  final String patientId;
  final String patientName;
  final DateTime requestedAt;
  final DateTime preferredSlot;
  final String modality;    // "diabetes", "hypertension", "anemia", "general", ...
  final String reason;      // free-form note from the patient
  final String status;      // "pending", "confirmed", "declined"

  const Appointment({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    required this.requestedAt,
    required this.preferredSlot,
    required this.modality,
    required this.reason,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'doctorId': doctorId,
        'patientId': patientId,
        'patientName': patientName,
        'requestedAt': requestedAt.toIso8601String(),
        'preferredSlot': preferredSlot.toIso8601String(),
        'modality': modality,
        'reason': reason,
        'status': status,
      };

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'] ?? '',
        doctorId: j['doctorId'] ?? '',
        patientId: j['patientId'] ?? '',
        patientName: j['patientName'] ?? '',
        requestedAt: DateTime.tryParse(j['requestedAt'] ?? '') ??
            DateTime.now(),
        preferredSlot:
            DateTime.tryParse(j['preferredSlot'] ?? '') ?? DateTime.now(),
        modality: j['modality'] ?? 'general',
        reason: j['reason'] ?? '',
        status: j['status'] ?? 'pending',
      );
}

/// AppointmentService - books an appointment with the patient's linked doctor.
///
/// Backend strategy: we reuse the existing `/mental-health/notifications`
/// endpoint (already wired for disease alerts) with `source: 'appointment_request'`
/// so the doctor's notification center shows it without any server-side
/// code changes. The clinical report body contains the preferred-slot ISO
/// string + reason, which the doctor UI can parse on render.
class AppointmentService {
  static const _key = 'appointments_local';
  static const _maxStored = 50;

  /// Book an appointment. Persists to MongoDB (durable, doctor-visible) AND
  /// keeps a local copy so the patient sees it offline / before the backend
  /// acknowledges. Pass [authToken] so the request is authenticated.
  static Future<Appointment> book({
    required String doctorId,
    required String patientId,
    required String patientName,
    required DateTime preferredSlot,
    String modality = 'general',
    String reason = '',
    String? authToken,
  }) async {
    var appt = Appointment(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      doctorId: doctorId,
      patientId: patientId,
      patientName: patientName,
      requestedAt: DateTime.now(),
      preferredSlot: preferredSlot,
      modality: modality,
      reason: reason,
    );

    // Canonical record in MongoDB. If it succeeds we adopt the server id so the
    // local copy and backend stay in sync; on failure we keep the local copy
    // and the request can be retried/refetched later (offline-friendly).
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/appointments'),
            headers: {
              'Content-Type': 'application/json',
              if (authToken != null) 'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({
              'doctorId': doctorId,
              'patientId': patientId,
              'patientName': patientName,
              'preferredSlot': preferredSlot.toIso8601String(),
              'modality': modality,
              'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['appointment'] is Map) {
          appt = Appointment.fromJson(
              Map<String, dynamic>.from(data['appointment'] as Map));
        }
      }
    } catch (_) {
      // Offline-friendly - local copy below is the fallback.
    }

    await _persistLocally(appt);
    return appt;
  }

  static Future<void> _persistLocally(Appointment appt) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.insert(0, jsonEncode(appt.toJson()));
    if (list.length > _maxStored) list.removeRange(_maxStored, list.length);
    await prefs.setStringList(_key, list);
  }

  /// Fetch appointments. Prefers MongoDB (the source of truth, synced across
  /// devices); falls back to the local cache when offline or unauthenticated.
  static Future<List<Appointment>> getAll({String? authToken}) async {
    if (authToken != null) {
      try {
        final response = await http.get(
          Uri.parse('${ApiConstants.baseUrl}/appointments/mine'),
          headers: {'Authorization': 'Bearer $authToken'},
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final appts = (data['appointments'] as List? ?? const [])
              .map((e) =>
                  Appointment.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          // Refresh the local cache so offline reads stay current.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(
              _key, appts.map((a) => jsonEncode(a.toJson())).toList());
          return appts;
        }
      } catch (_) {
        // fall through to local cache
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? const [];
    return list
        .map((s) {
          try {
            return Appointment.fromJson(
                Map<String, dynamic>.from(jsonDecode(s) as Map));
          } catch (_) {
            return null;
          }
        })
        .whereType<Appointment>()
        .toList();
  }

  /// Convenience: natural-language request from the chatbot.
  /// The chatbot passes a free-text preferred-time string (e.g. "tomorrow 10 am").
  /// We parse a few common patterns, fall back to "+1 day same time".
  static DateTime parseSlot(String raw) {
    final lower = raw.toLowerCase().trim();
    final now = DateTime.now();

    // "today" / "tonight"
    if (lower.contains('today') || lower.contains('tonight')) {
      return _withTime(now, _extractHour(lower) ?? 18);
    }
    // "tomorrow"
    if (lower.contains('tomorrow')) {
      final t = now.add(const Duration(days: 1));
      return _withTime(t, _extractHour(lower) ?? 10);
    }
    // "next week"
    if (lower.contains('next week')) {
      return _withTime(now.add(const Duration(days: 7)),
          _extractHour(lower) ?? 10);
    }
    // "in X days"
    final inDays =
        RegExp(r'in\s+(\d+)\s+day').firstMatch(lower);
    if (inDays != null) {
      final days = int.tryParse(inDays.group(1)!) ?? 1;
      return _withTime(now.add(Duration(days: days)),
          _extractHour(lower) ?? 10);
    }
    // Weekday name
    const weekdays = {
      'monday': 1,
      'tuesday': 2,
      'wednesday': 3,
      'thursday': 4,
      'friday': 5,
      'saturday': 6,
      'sunday': 7,
    };
    for (final entry in weekdays.entries) {
      if (lower.contains(entry.key)) {
        final target = entry.value;
        int diff = (target - now.weekday) % 7;
        if (diff == 0) diff = 7;
        return _withTime(now.add(Duration(days: diff)),
            _extractHour(lower) ?? 10);
      }
    }
    // Default: +1 day at 10 AM
    return _withTime(now.add(const Duration(days: 1)), 10);
  }

  static DateTime _withTime(DateTime d, int hour) =>
      DateTime(d.year, d.month, d.day, hour, 0);

  static int? _extractHour(String s) {
    // Match "10 am", "2pm", "14:00"
    final m = RegExp(r'(\d{1,2})(?::\d{2})?\s*(am|pm)?').firstMatch(s);
    if (m == null) return null;
    var h = int.tryParse(m.group(1)!);
    if (h == null) return null;
    final ap = m.group(2);
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (h < 0 || h > 23) return null;
    return h;
  }
}
