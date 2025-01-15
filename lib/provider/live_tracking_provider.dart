// ignore_for_file: unused_field

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:parentseye_parent/models/parent_student_model.dart.dart';
import 'package:parentseye_parent/provider/geofences_provider.dart';
import 'package:provider/provider.dart';

import '../constants/api_constants.dart';
import '../models/devices_model.dart';
import '../models/geofencing_model.dart';
import '../models/positions_model.dart';

class TrackingProvider with ChangeNotifier {
  Device? _device;
  List<PositionsModel> _positions = [];
  Timer? _timer;
  bool _isLoading = false;
  String? _error;
  int _retryCount = 0;
  static const int maxRetries = 3;
  static const Duration timeoutDuration = Duration(seconds: 10);
  static const Duration updateInterval = Duration(seconds: 10);

  LatLng? _currentAnimatedPosition;
  double _currentAnimatedBearing = 0.0;
  Timer? _animationTimer;
  DateTime? _lastUpdateTime;
  LatLng? _lastPosition;
  static const int animationFPS = 30;
  static const Duration animationFrameDuration =
      Duration(milliseconds: 1000 ~/ 30);

  List<LatLng> _polylineCoordinates = [];

  List<LatLng> get polylineCoordinates => _polylineCoordinates;
  LatLng? get currentAnimatedPosition => _currentAnimatedPosition;
  double get currentAnimatedBearing => _currentAnimatedBearing;
  Device? get device => _device;
  List<PositionsModel> get positions => _positions;
  bool get isLoading => _isLoading;
  String? get error => _error;
  StudentDetails? _studentDetails;

  final String _username = 'schoolmaster';
  final String _password = '123456';
  late final String _authHeader;

  TrackingProvider() {
    _authHeader = 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
  }

  Future<void> fetchDevice(StudentDetails studentDetails) async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConstants.devicesUrl}?deviceId=${studentDetails.deviceId}'),
        headers: {'Authorization': _authHeader},
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          _device = Device.fromJson(data[0]);
          await fetchPositions(studentDetails.deviceId);
        }
      }
    } catch (e) {
      _error = 'Connection error: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPositions(String deviceId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.positionsUrl}?deviceId=$deviceId'),
        headers: {'Authorization': _authHeader},
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          List<PositionsModel> newPositions =
              data.map((json) => PositionsModel.fromJson(json)).toList();

          if (_positions.isEmpty || newPositions.last != _positions.last) {
            _positions = newPositions;
            _updateAnimation(newPositions.last);
          }
        }
      }
    } catch (e) {
      _error = 'Position update failed: ${e.toString()}';
    }
    notifyListeners();
  }

  void _updateAnimation(PositionsModel newPosition) {
    LatLng targetLatLng = LatLng(newPosition.latitude, newPosition.longitude);
    double targetBearing = newPosition.course;

    if (_currentAnimatedPosition == null) {
      _currentAnimatedPosition = targetLatLng;
      _currentAnimatedBearing = targetBearing;
      _polylineCoordinates.add(targetLatLng);
      _lastUpdateTime = DateTime.now();
      notifyListeners();
      return;
    }

    double distance = _calculateDistance(
        _currentAnimatedPosition!.latitude,
        _currentAnimatedPosition!.longitude,
        targetLatLng.latitude,
        targetLatLng.longitude);

    if (distance > 500) {
      _polylineCoordinates.clear();
      _polylineCoordinates.add(targetLatLng);
      _currentAnimatedPosition = targetLatLng;
      _currentAnimatedBearing = targetBearing;
      _lastUpdateTime = DateTime.now();
      notifyListeners();
      return;
    }

    _animationTimer?.cancel();

    DateTime now = DateTime.now();
    Duration timeSinceLastUpdate = _lastUpdateTime != null
        ? now.difference(_lastUpdateTime!)
        : Duration.zero;

    Duration animationDuration = timeSinceLastUpdate.inSeconds < 10
        ? timeSinceLastUpdate
        : const Duration(seconds: 5);

    LatLng startLatLng = _currentAnimatedPosition!;
    double startBearing = _currentAnimatedBearing;
    double bearingDiff =
        _calculateShortestRotation(startBearing, targetBearing);

    int totalFrames = (animationDuration.inMilliseconds / (1000 ~/ 30)).round();
    int currentFrame = 0;

    _animationTimer = Timer.periodic(
      const Duration(milliseconds: 1000 ~/ 30),
      (timer) {
        currentFrame++;
        if (currentFrame >= totalFrames) {
          _currentAnimatedPosition = targetLatLng;
          _currentAnimatedBearing = targetBearing;
          _polylineCoordinates.add(targetLatLng);
          _lastUpdateTime = now;
          timer.cancel();
        } else {
          double progress = currentFrame / totalFrames;
          progress = _smoothStep(progress);

          _currentAnimatedPosition =
              _interpolateLatLng(startLatLng, targetLatLng, progress);
          _currentAnimatedBearing = startBearing + bearingDiff * progress;

          _polylineCoordinates.add(_currentAnimatedPosition!);
        }

        if (_polylineCoordinates.length > 1000) {
          _polylineCoordinates.removeAt(0);
        }

        notifyListeners();
      },
    );
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _calculateShortestRotation(double start, double end) {
    double diff = end - start;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  LatLng _interpolateLatLng(LatLng start, LatLng end, double fraction) {
    double lat1 = _degreesToRadians(start.latitude);
    double lon1 = _degreesToRadians(start.longitude);
    double lat2 = _degreesToRadians(end.latitude);
    double lon2 = _degreesToRadians(end.longitude);

    double d = 2 *
        asin(sqrt(pow(sin((lat2 - lat1) / 2), 2) +
            cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)));

    if (d == 0) return start;

    double A = sin((1 - fraction) * d) / sin(d);
    double B = sin(fraction * d) / sin(d);

    double x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2);
    double y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2);
    double z = A * sin(lat1) + B * sin(lat2);

    double lat = atan2(z, sqrt(x * x + y * y));
    double lon = atan2(y, x);

    return LatLng(_radiansToDegrees(lat), _radiansToDegrees(lon));
  }

  double _smoothStep(double x) {
    return x * x * (3 - 2 * x);
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  double _radiansToDegrees(double radians) {
    return radians * 180 / pi;
  }

  void startTracking(String deviceId) {
    _timer?.cancel();

    fetchPositions(deviceId);

    _timer = Timer.periodic(updateInterval, (timer) {
      fetchPositions(deviceId);
    });
  }

  void checkGeofenceStatus(BuildContext context) {
    if (_positions.isEmpty) return;

    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);
    final geofences = geofenceProvider.geofences;
    final currentPosition = _positions.last;

    for (var geofence in geofences) {
      bool isInside = _isPositionInsideGeofence(currentPosition, geofence);

      if (isInside && !geofence.isCrossed) {
        String arrivalTime = DateFormat('HH:mm:ss').format(DateTime.now());
        geofenceProvider.updateGeofenceStatus(
            geofence.id, true, arrivalTime, null);
      } else if (!isInside && geofence.isCrossed) {
        String departureTime = DateFormat('HH:mm:ss').format(DateTime.now());
        geofenceProvider.updateGeofenceStatus(
            geofence.id, true, geofence.arrivalTime, departureTime);
      }
    }
  }

  bool _isPositionInsideGeofence(PositionsModel position, Geofence geofence) {
    double distance = _calculateDistance(
      position.latitude,
      position.longitude,
      geofence.center.latitude,
      geofence.center.longitude,
    );
    return distance <= geofence.radius;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationTimer?.cancel();
    super.dispose();
  }
}
