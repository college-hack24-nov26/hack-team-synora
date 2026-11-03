import '../core/constants/api_constants.dart';
import 'api_service.dart';

class AuthService {
  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    required String role,
    String? phone,
    // Patient fields
    String? dateOfBirth,
    String? bloodGroup,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelationship,
    // Doctor fields
    String? specialization,
    String? licenseNumber,
    String? hospital,
    int? yearsOfExperience,
  }) async {
    final api = ApiService();

    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'name': name,
      'role': role,
    };

    if (phone != null) body['phone'] = phone;

    if (role == 'patient') {
      if (dateOfBirth != null) body['dateOfBirth'] = dateOfBirth;
      if (bloodGroup != null) body['bloodGroup'] = bloodGroup;
      if (emergencyContactName != null) {
        body['emergencyContactName'] = emergencyContactName;
      }
      if (emergencyContactPhone != null) {
        body['emergencyContactPhone'] = emergencyContactPhone;
      }
      if (emergencyContactRelationship != null) {
        body['emergencyContactRelationship'] = emergencyContactRelationship;
      }
    } else if (role == 'doctor') {
      if (specialization != null) body['specialization'] = specialization;
      if (licenseNumber != null) body['licenseNumber'] = licenseNumber;
      if (hospital != null) body['hospital'] = hospital;
      if (yearsOfExperience != null) {
        body['yearsOfExperience'] = yearsOfExperience;
      }
    }

    return api.post(ApiConstants.register, body);
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final api = ApiService();
    return api.post(ApiConstants.login, {
      'email': email,
      'password': password,
    });
  }
}
