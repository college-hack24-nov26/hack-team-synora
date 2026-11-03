class ApiConstants {
  static const String baseUrl = 'https://medicoscope-server.onrender.com/api';

  // Chatbot
  static const String chatbotBaseUrl =
      'https://medicoscope-chatbot-mu7p.onrender.com';

  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';

  // Users
  static const String profile = '/users/profile';

  // Doctors
  static const String doctorPatients = '/doctors/patients';

  // Patients
  static const String patientLink = '/patients/link';
  static const String patientRecords = '/patients/records';
  static const String patientDoctor = '/patients/doctor';

  // Detections
  static const String detections = '/detections';

  // Mental Health
  static const String mentalHealthAnalyze = '/mental-health/analyze';
  static const String mentalHealthNotifications =
      '/mental-health/notifications';

  // Rewards
  static const String rewardsRedeem = '/rewards/redeem';

  // CardioScope (Heart Sound Analysis)
  static const String cardioBaseUrl = 'https://cardio-l3eb.onrender.com';
  static const String cardioPredict = '/predict';

  // Vitals Monitoring (Python chatbot server)
  static const String vitalsStart = '/vitals/start';
  static const String vitalsTick = '/vitals/tick';
  static const String vitalsDoctorAlerts = '/vitals/alerts/doctor';
  static const String vitalsPatientAlerts = '/vitals/alerts/patient';
  static const String vitalsSession = '/vitals/session';

  // Vitals Summaries (Node.js server - persisted)
  static const String vitalsSummary = '/vitals/summary';
  static const String vitalsSummaries = '/vitals/summaries';

  // Medical Summary (for chatbot context)
  static const String patientMedicalSummary = '/patients/medical-summary';

  // Chat History
  static const String chatMessage = '/chat/message';
  static const String chatHistory = '/chat/history';
  static const String chatSession = '/chat/session';

  // MindSpace History
  static const String mindspaceSession = '/mindspace/session';
  static const String mindspaceHistory = '/mindspace/history';
  static const String mindspaceDoctor = '/mindspace/doctor';

  // Rewards (DB-synced)
  static const String rewards = '/rewards';

  // Claimed Rewards
  static const String claimedRewards = '/claimed-rewards';

  // Admin
  static const String adminPatients = '/admin/patients';
  static const String adminDoctors = '/admin/doctors';
  static const String adminStats = '/admin/stats';
  static const String adminNearbyDoctors = '/admin/nearby-doctors';

  // Nearby Doctors (patient search)
  static const String nearbyDoctorsSearch = '/nearby-doctors/search';
  static const String nearbyDoctorsSpecializations = '/nearby-doctors/specializations';
}
