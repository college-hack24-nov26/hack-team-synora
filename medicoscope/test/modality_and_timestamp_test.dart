import 'package:flutter_test/flutter_test.dart';
import 'package:medicoscope/screens/notifications/notifications_screen.dart';

void main() {
  group('NotificationsScreen.formatReadableTimestamp Tests', () {
    test('formatReadableTimestamp handles null and empty inputs safely', () {
      expect(NotificationsScreen.formatReadableTimestamp(null), equals('N/A'));
      expect(NotificationsScreen.formatReadableTimestamp(''), equals('N/A'));
    });

    test('formatReadableTimestamp formats current timestamp with Today and Just now', () {
      final now = DateTime.now();
      final formatted = NotificationsScreen.formatReadableTimestamp(now);

      expect(formatted, contains('Today'));
      expect(formatted, contains('Just now'));
      // Expect 12-hour AM/PM format
      expect(formatted, anyOf(contains('AM'), contains('PM')));
    });

    test('formatReadableTimestamp formats earlier today with relative hours/minutes', () {
      final earlierToday = DateTime.now().subtract(const Duration(hours: 2));
      final formatted = NotificationsScreen.formatReadableTimestamp(earlierToday);

      expect(formatted, contains('Today'));
      expect(formatted, contains('2h ago'));
    });

    test('formatReadableTimestamp formats yesterday date', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final formatted = NotificationsScreen.formatReadableTimestamp(yesterday);

      expect(formatted, contains('Yesterday'));
      expect(formatted, anyOf(contains('AM'), contains('PM')));
    });

    test('formatReadableTimestamp formats older dates with month, day, year', () {
      final pastDate = DateTime(2025, 10, 15, 1, 46, 22);
      final formatted = NotificationsScreen.formatReadableTimestamp(pastDate);

      expect(formatted, contains('Oct 15, 2025'));
      expect(formatted, contains('1:46:22 AM'));
    });
  });

  group('NotificationsScreen.classifyItem Modality Classification Tests', () {
    test('Skin Cancer / Dermatology classification', () {
      final item1 = {'source': 'skin_scan', 'report': 'Melanoma high confidence'};
      final item2 = {'source': 'disease_screening', 'report': 'Squamous cell carcinoma detected'};
      final item3 = {'source': 'general', 'transcript': 'Actinic keratosis lesion suspected'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.skinCancer));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.skinCancer));
      expect(NotificationsScreen.classifyItem(item3), equals(NotificationModality.skinCancer));
    });

    test('Cardiac / Heart Auscultation classification', () {
      final item1 = {'source': 'cardiac_auscultation', 'report': 'Systolic heart murmur detected'};
      final item2 = {'source': 'heart', 'transcript': 'Arrhythmia identified during acoustic recording'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.cardiac));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.cardiac));
    });

    test('Anemia / Conjunctival Pallor classification', () {
      final item1 = {'source': 'disease_screening_anemia', 'report': 'Estimated Hb 6.8 g/dL'};
      final item2 = {'source': 'general', 'report': 'Severe conjunctival pallor detected on eyelid'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.anemia));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.anemia));
    });

    test('Respiratory Acoustics classification', () {
      final item1 = {'source': 'disease_screening_respiratory', 'report': 'Fine crackles and wheezing heard'};
      final item2 = {'source': 'audio_screening', 'transcript': 'Lung sound acoustic analysis'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.respiratory));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.respiratory));
    });

    test('Diabetic Retinopathy classification', () {
      final item1 = {'source': 'retinal_fundus', 'report': 'Microaneurysms seen on macular fundus'};
      final item2 = {'source': 'disease_screening_diabeticRetinopathy', 'report': 'High risk'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.retinopathy));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.retinopathy));
    });

    test('Vitals & Telemetry classification', () {
      final item1 = {'source': 'vitals_alert', 'vital_type': 'blood_pressure', 'report': 'Stage 2 Hypertension'};
      final item2 = {'source': 'sensor', 'report': 'SpO2 86% Hypoxia alert'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.vitals));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.vitals));
    });

    test('MindSpace / Mental Health classification', () {
      final item1 = {'source': 'mindspace', 'report': 'PHQ-9 screening score 18'};
      final item2 = {'source': 'chat', 'transcript': 'MindSpace audio check-in voice biomarker'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.mindSpace));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.mindSpace));
    });

    test('Appointment Request classification', () {
      final item1 = {'source': 'appointment_request', 'report': 'Appointment request for tomorrow morning'};
      final item2 = {'source': 'general', 'report': 'Patient preferred slot: Thursday 10:00 AM'};

      expect(NotificationsScreen.classifyItem(item1), equals(NotificationModality.appointments));
      expect(NotificationsScreen.classifyItem(item2), equals(NotificationModality.appointments));
    });
  });
}
