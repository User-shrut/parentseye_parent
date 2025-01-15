import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:parentseye_parent/constants/api_constants.dart';
import 'package:parentseye_parent/constants/app_colors.dart';
import 'package:parentseye_parent/models/login_response_model.dart';
import 'package:parentseye_parent/models/parent_student_model.dart.dart';
import 'package:parentseye_parent/provider/geofences_provider.dart';
import 'package:parentseye_parent/screens/parent_login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/geofencing_model.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  bool _isLoading = false;
  bool _fullAccess = false;
  late Future<void> initialized;
  List<Geofence> _geofences = [];
  ParentStudentModel? _parentStudentModel;
  LoginType? _loginType;
  SchoolLoginResponse? _schoolData;
  BranchLoginResponse? _branchData;

  List<Geofence> get geofences => _geofences;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null;
  bool get hasFullAccess => _fullAccess;
  ParentStudentModel? get parentStudentModel => _parentStudentModel;
  LoginType? get loginType => _loginType;
  SchoolLoginResponse? get schoolData => _schoolData;
  BranchLoginResponse? get branchData => _branchData;

  AuthProvider() {
    initialized = tryAutoLogin();
  }

  Future<void> fetchGeofences() async {
    if (_parentStudentModel == null || _parentStudentModel!.children.isEmpty) {
      return;
    }

    final geofenceProvider = GeofenceProvider();
    for (var child in _parentStudentModel!.children) {
      await geofenceProvider.fetchGeofences(child.deviceId);
      _geofences.addAll(geofenceProvider.geofences);
    }
    notifyListeners();
  }

  Future<String?> login({
    required String username,
    required String password,
  }) async {
    _setLoading(true);
    try {
      final parentResult = await _attemptParentLogin(username, password);
      if (parentResult == null) return null;

      final branchResult = await _attemptBranchLogin(username, password);
      if (branchResult == null) return null;

      return 'Invalid credentials. Please check your username and password.';
    } finally {
      _setLoading(false);
    }
  }

  Future<String?> _attemptParentLogin(String email, String password) async {
    final url = Uri.parse(ApiConstants.login);
    try {
      final response = await http.post(
        url,
        body: jsonEncode({'email': email, 'password': password}),
        headers: {'Content-Type': 'application/json'},
      );

      final responseData = jsonDecode(response.body);
      if (responseData['success'] == true) {
        _token = responseData['token'];
        _fullAccess = responseData['fullAccess'] ?? false;
        _loginType = LoginType.parent;

        if (_token != null) {
          await _saveLoginData(
            token: _token!,
            loginType: LoginType.parent,
            data: responseData,
          );
          return null;
        }
      }
      return responseData['message'] ?? 'Login failed';
    } catch (e) {
      return 'Login failed: ${e.toString()}';
    }
  }

  Future<String?> _attemptBranchLogin(String username, String password) async {
    final url = Uri.parse(ApiConstants.branchLogin);
    try {
      final response = await http.post(
        url,
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
        headers: {'Content-Type': 'application/json'},
      );

      final responseData = jsonDecode(response.body);
      if (responseData['success'] == true) {
        _branchData = BranchLoginResponse.fromJson(responseData);
        _token = _branchData!.token;
        _loginType = LoginType.branch;

        await _saveLoginData(
          token: _token!,
          loginType: LoginType.branch,
          data: responseData,
        );
        return null;
      }
      return responseData['message'] ?? 'Login failed';
    } catch (e) {
      return 'Login failed: ${e.toString()}';
    }
  }

  Future<bool> _showLogoutConfirmation(BuildContext context) async {
    return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Confirm Logout',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryColor,
                ),
              ),
              content: const Text('Are you sure you want to logout?'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'Logout',
                    style: TextStyle(color: AppColors.primaryColor),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void logout(BuildContext context) async {
    if (await _showLogoutConfirmation(context)) {
      _token = null;
      _loginType = null;
      _fullAccess = false;
      _geofences.clear();
      _parentStudentModel = null;
      _schoolData = null;
      _branchData = null;
      _isLoading = false;

      await _clearAllData();
      notifyListeners();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const ParentalLogin()),
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> _saveLoginData({
    required String token,
    required LoginType loginType,
    required Map<String, dynamic> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('login_type', loginType.toString());
    await prefs.setString('login_data', jsonEncode(data));
  }

  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('auth_token');
    final savedLoginType = prefs.getString('login_type');
    final savedData = prefs.getString('login_data');

    if (savedToken != null && savedLoginType != null && savedData != null) {
      _token = savedToken;
      _loginType = LoginType.values.firstWhere(
        (e) => e.toString() == savedLoginType,
        orElse: () => LoginType.parent,
      );

      final data = jsonDecode(savedData);
      if (_loginType == LoginType.branch) {
        _branchData = BranchLoginResponse.fromJson(data);
      }

      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
