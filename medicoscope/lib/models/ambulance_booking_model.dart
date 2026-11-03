class AmbulanceBooking {
  final String bookingId;
  final String patientId;
  final String patientName;
  final String hospitalName;
  final double hospitalLatitude;
  final double hospitalLongitude;
  final double patientLatitude;
  final double patientLongitude;
  final String paramedicName;
  final String driverPhone;
  final String vehicleNumber;
  final int initialEtaMinutes;
  final String status;
  final String criticalAlert;
  final DateTime dispatchedAt;

  const AmbulanceBooking({
    required this.bookingId,
    required this.patientId,
    required this.patientName,
    required this.hospitalName,
    required this.hospitalLatitude,
    required this.hospitalLongitude,
    required this.patientLatitude,
    required this.patientLongitude,
    required this.paramedicName,
    required this.driverPhone,
    required this.vehicleNumber,
    required this.initialEtaMinutes,
    required this.status,
    required this.criticalAlert,
    required this.dispatchedAt,
  });

  factory AmbulanceBooking.fromJson(Map<String, dynamic> json) {
    final hospLoc = json['hospitalLocation'] as Map<String, dynamic>? ?? {};
    final patLoc = json['patientLocation'] as Map<String, dynamic>? ?? {};

    return AmbulanceBooking(
      bookingId: json['bookingId'] as String? ?? 'AMB-${DateTime.now().millisecondsSinceEpoch}',
      patientId: json['patientId'] as String? ?? '',
      patientName: json['patientName'] as String? ?? 'Patient',
      hospitalName: json['hospitalName'] as String? ?? 'City Emergency Hospital',
      hospitalLatitude: (hospLoc['latitude'] as num?)?.toDouble() ?? 0.0,
      hospitalLongitude: (hospLoc['longitude'] as num?)?.toDouble() ?? 0.0,
      patientLatitude: (patLoc['latitude'] as num?)?.toDouble() ?? 0.0,
      patientLongitude: (patLoc['longitude'] as num?)?.toDouble() ?? 0.0,
      paramedicName: json['paramedicName'] as String? ?? 'Paramedic Rapid Response Team',
      driverPhone: json['driverPhone'] as String? ?? '108',
      vehicleNumber: json['vehicleNumber'] as String? ?? 'ALS-ICU-108',
      initialEtaMinutes: json['etaMinutes'] as int? ?? 8,
      status: json['status'] as String? ?? 'dispatched',
      criticalAlert: json['criticalAlert'] as String? ?? 'Critical Health Event',
      dispatchedAt: DateTime.tryParse(json['dispatchedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'patientId': patientId,
        'patientName': patientName,
        'hospitalName': hospitalName,
        'hospitalLocation': {
          'latitude': hospitalLatitude,
          'longitude': hospitalLongitude,
        },
        'patientLocation': {
          'latitude': patientLatitude,
          'longitude': patientLongitude,
        },
        'paramedicName': paramedicName,
        'driverPhone': driverPhone,
        'vehicleNumber': vehicleNumber,
        'etaMinutes': initialEtaMinutes,
        'status': status,
        'criticalAlert': criticalAlert,
        'dispatchedAt': dispatchedAt.toIso8601String(),
      };
}

