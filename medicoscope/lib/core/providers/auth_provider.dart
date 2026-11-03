import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  String? _token;
  bool _isLoading = true;

  UserModel? get user => _user;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isLoading => _isLoading;
  bool get isPatient => _user?.role == 'patient';
  bool get isDoctor => _user?.role == 'doctor';
  bool get isAdmin => _user?.role == 'admin';
  String get userRole => _user?.role ?? '';

  AuthProvider() {
    tryAutoLogin();
  }

  Future<void> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('auth_token');
      final storedUser = prefs.getString('auth_user');

      if (storedToken != null && storedUser != null) {
        // Check if token is expired
        if (JwtDecoder.isExpired(storedToken)) {
          await _clearStorage();
        } else {
          _token = storedToken;
          _user = UserModel.fromJson(jsonDecode(storedUser));
        }
      }
    } catch (e) {
      await _clearStorage();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final response = await AuthService.login(
        email: email,
        password: password,
      );

      _token = response['token'];
      _user = UserModel.fromJson(response['user']);
      await _persistAuth();
      notifyListeners();
      return true;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Connection failed. Is the server running?');
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String role,
    String? phone,
    String? dateOfBirth,
    String? bloodGroup,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelationship,
    String? specialization,
    String? licenseNumber,
    String? hospital,
    int? yearsOfExperience,
  }) async {
    try {
      final response = await AuthService.register(
        email: email,
        password: password,
        name: name,
        role: role,
        phone: phone,
        dateOfBirth: dateOfBirth,
        bloodGroup: bloodGroup,
        emergencyContactName: emergencyContactName,
        emergencyContactPhone: emergencyContactPhone,
        emergencyContactRelationship: emergencyContactRelationship,
        specialization: specialization,
        licenseNumber: licenseNumber,
        hospital: hospital,
        yearsOfExperience: yearsOfExperience,
      );

      _token = response['token'];
      _user = UserModel.fromJson(response['user']);
      await _persistAuth();
      notifyListeners();
      return true;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Connection failed. Is the server running?');
    }
  }

  Future<void> refreshUser() async {
    if (_token == null) return;
    try {
      final api = ApiService(token: _token);
      final response = await api.get('/users/profile');
      final userData = response['user'] as Map<String, dynamic>?;
      if (userData != null) {
        _user = UserModel.fromJson(userData);
        await _persistAuth();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    _user = null;
    _token = null;
    await _clearStorage();
    notifyListeners();
  }

  Future<void> _persistAuth() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) prefs.setString('auth_token', _token!);
    if (_user != null) {
      prefs.setString('auth_user', jsonEncode(_user!.toJson()));
    }
  }

  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('auth_token');
    prefs.remove('auth_user');
  }
}
