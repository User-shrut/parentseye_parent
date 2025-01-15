import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:parentseye_parent/constants/api_constants.dart';
import 'package:parentseye_parent/models/branch_login_related/branch_tracking_model.dart';

class VehicleTrackingProvider with ChangeNotifier {
  Map<int, Map<String, dynamic>> _deviceData = {};
  Timer? _refreshTimer;

  bool _isInitialFetchComplete = false;

  bool get isInitialFetchComplete => _isInitialFetchComplete;
  final String _username = 'schoolmaster';
  final String _password = '123456';

  String _basicAuth() {
    String credentials = '$_username:$_password';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  Map<String, dynamic>? getDeviceData(int deviceId) {
    return _deviceData[deviceId];
  }

  void startPeriodicUpdates(List<int> deviceIds) {
    initialFetchForDevices(deviceIds).then((_) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        for (var deviceId in deviceIds) {
          updateDeviceData(deviceId);
        }
      });
    });
  }

  Future<void> initialFetchForDevices(List<int> deviceIds) async {
    try {
      final List<Future<void>> fetchFutures = deviceIds.map((deviceId) async {
        try {
          final futures = await Future.wait([
            getPositions(deviceId),
            getDevice(deviceId),
          ]);

          final positions = futures[0] as List<Position>;
          final devices = futures[1] as List<DeviceBranch>;

          if (positions.isNotEmpty && devices.isNotEmpty) {
            final latest = positions.first;
            final device = devices.first;

            final newData = {
              'latitude': latest.latitude,
              'longitude': latest.longitude,
              'speed': latest.speed ?? 0,
              'lastUpdate': device.lastUpdate,
              'motion': latest.attributes?.motion ?? false,
              'status': device.status,
              'positionId': latest.id,
              'attributes': {
                'ignition': latest.attributes?.ignition ?? false,
                'motion': latest.attributes?.motion ?? false,
                'sat': latest.attributes?.sat ?? 0,
                'distance': latest.attributes?.distance ?? 0,
                'charge': latest.attributes?.charge ?? false,
                'totalDistance': latest.attributes?.totalDistance ?? 0
              },
              'address': latest.address ?? 'Fetching address...',
            };

            _deviceData[deviceId] = newData;
          }
        } catch (e) {
          log('Error fetching initial data for device $deviceId: $e');
          _deviceData[deviceId] = {
            'error': true,
            'address': 'Error fetching data',
            'status': 'offline',
            'positionId': 0,
          };
        }
      }).toList();

      await Future.wait(fetchFutures);
      _isInitialFetchComplete = true;
      notifyListeners();

      _fetchAddressesInBackground(deviceIds);
    } catch (e) {
      log('Error in bulk fetch: $e');
      _isInitialFetchComplete = true;
      notifyListeners();
    }
  }

  Future<void> _fetchAddressesInBackground(List<int> deviceIds) async {
    for (var deviceId in deviceIds) {
      if (_deviceData[deviceId] != null &&
          _deviceData[deviceId]?['latitude'] != null &&
          _deviceData[deviceId]?['longitude'] != null) {
        try {
          final address = await getAddressFromLatLng(
            _deviceData[deviceId]!['latitude'],
            _deviceData[deviceId]!['longitude'],
          );
          _deviceData[deviceId]?['address'] = address;
          notifyListeners();
        } catch (e) {
          log('Error fetching address for device $deviceId: $e');
        }
      }
    }
  }

  Future<String> getAddressFromLatLng(double lat, double lng) async {
    try {
      final List<Placemark> placemarks =
          await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final List<String> addressParts = [
          if (place.street != null && place.street!.isNotEmpty) place.street!,
          if (place.subLocality != null && place.subLocality!.isNotEmpty)
            place.subLocality!,
          if (place.locality != null && place.locality!.isNotEmpty)
            place.locality!,
          if (place.administrativeArea != null &&
              place.administrativeArea!.isNotEmpty)
            place.administrativeArea!,
        ];

        return addressParts.join(', ');
      }
      return 'Address not found';
    } catch (e) {
      log('Error getting address: $e');
      return 'Error fetching address';
    }
  }

  Future<void> updateDeviceData(int deviceId) async {
    try {
      final positions = await getPositions(deviceId);
      final devices = await getDevice(deviceId);

      if (positions.isNotEmpty && devices.isNotEmpty) {
        final latest = positions.first;
        final device = devices.first;

        final newData = {
          'latitude': latest.latitude,
          'longitude': latest.longitude,
          'speed': latest.speed ?? 0,
          'lastUpdate': device.lastUpdate,
          'motion': latest.attributes?.motion ?? false,
          'status': device.status,
          'positionId': latest.id,
          'attributes': {
            'ignition': latest.attributes?.ignition ?? false,
            'motion': latest.attributes?.motion ?? false,
            'sat': latest.attributes?.sat ?? 0,
            'distance': latest.attributes?.distance ?? 0,
            'charge': latest.attributes?.charge ?? false,
            'totalDistance': latest.attributes?.totalDistance ?? 0
          },
          'address': latest.address ?? 'Fetching address...',
        };

        _deviceData[deviceId] = newData;
        notifyListeners();

        if (latest.address == null &&
            latest.latitude != null &&
            latest.longitude != null) {
          final address =
              await getAddressFromLatLng(latest.latitude!, latest.longitude!);
          if (_deviceData[deviceId] != null) {
            _deviceData[deviceId]?['address'] = address;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      log('Error updating device data: $e');
      if (!_deviceData.containsKey(deviceId)) {
        _deviceData[deviceId] = {
          'address': 'Error updating location data',
          'motion': false,
          'status': 'offline',
          'positionId': 0,
        };
        notifyListeners();
      }
    }
  }

  void stopPeriodicUpdates() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<List<Position>> getPositions(int deviceId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.positionsUrl}?deviceId=$deviceId'),
        headers: {'Authorization': _basicAuth()},
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => Position.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load positions: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load positions: $e');
    }
  }

  Future<List<DeviceBranch>> getDevice(int id) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.devicesUrl}?id=$id'),
        headers: {'Authorization': _basicAuth()},
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => DeviceBranch.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load device: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load device: $e');
    }
  }

  Future<Map<String, dynamic>> getCurrentLocation(int deviceId) async {
    try {
      final positions = await getPositions(deviceId);
      if (positions.isNotEmpty) {
        final latest = positions.first;
        return {
          'latitude': latest.latitude,
          'longitude': latest.longitude,
          'speed': latest.speed ?? 0.0,
          'course': latest.course ?? 0.0,
          'lastUpdate': latest.serverTime,
          'attributes': {
            'ignition': latest.attributes?.ignition ?? false,
            'motion': latest.attributes?.motion ?? false,
            'sat': latest.attributes?.sat ?? 0,
            'distance': latest.attributes?.distance ?? 0,
            'charge': latest.attributes?.charge ?? false,
            'totalDistance': latest.attributes?.totalDistance ?? 0
          },
        };
      }
      throw Exception('No positions available');
    } catch (e) {
      throw Exception('Failed to get current location: $e');
    }
  }

  Future<bool> isDeviceMoving(int deviceId) async {
    try {
      final positions = await getPositions(deviceId);
      if (positions.isNotEmpty) {
        return positions.first.attributes!.motion!;
      }
      return false;
    } catch (e) {
      throw Exception('Failed to check device motion: $e');
    }
  }
}
