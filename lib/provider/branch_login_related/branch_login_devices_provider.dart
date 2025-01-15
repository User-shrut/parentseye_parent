import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:parentseye_parent/constants/api_constants.dart';
import 'package:parentseye_parent/models/branch_login_related/branch_login_devices_model.dart';

class DeviceBranchLoginProvider with ChangeNotifier {
  List<DeviceBranchLogin> _devices = [];
  bool _isLoading = false;
  String? _error;

  List<DeviceBranchLogin> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchDevices(String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(ApiConstants.getBranchLoginDevices),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = json.decode(response.body);
      if (response.statusCode == 200 && responseData['devices'] != null) {
        _devices = (responseData['devices'] as List)
            .map((device) => DeviceBranchLogin.fromJson(device))
            .toList();
      } else {
        _error = responseData['message'] ?? 'Failed to fetch devices';
      }
    } catch (e) {
      _error = 'Error fetching devices: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
