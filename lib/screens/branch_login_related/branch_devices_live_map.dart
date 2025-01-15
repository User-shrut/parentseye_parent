import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:parentseye_parent/constants/app_colors.dart';
import 'package:parentseye_parent/provider/branch_login_related/branch_tracking_provider.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:url_launcher/url_launcher.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const LiveTrackingScreen({
    Key? key,
    required this.deviceId,
    required this.deviceName,
  }) : super(key: key);

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with TickerProviderStateMixin {
  final VehicleTrackingProvider _trackingProvider = VehicleTrackingProvider();
  GoogleMapController? _mapController;
  Timer? _locationTimer;
  Timer? _animationTimer;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _completeRoute = [];
  LatLng? _currentLocation;
  LatLng? _previousLocation;
  LatLng? _targetLocation;
  double _currentSpeed = 0;
  double _currentBearing = 0;
  bool _followVehicle = true;
  DateTime? _lastUpdate;
  bool _isMoving = false;
  bool _ignition = false;
  BitmapDescriptor? _customIcon;
  double _animationProgress = 0;
  bool isPanelOpen = false;
  String _currentAddress = "Fetching address...";
  static const double animationDuration = 10.0;
  static const double animationUpdateInterval = 0.016;

  static const double speedThreshold = 2.0;
  static const double overspeedThreshold = 60.0;
  late double _minPanelHeight;
  late double _maxPanelHeight;
  final PanelController _panelController = PanelController();

  MapType _currentMapType = MapType.normal;
  bool _showMapTypeToggles = false;
  bool _isSatelliteEnabled = false;
  bool _isTerrainEnabled = false;

  double _totalDistance = 0;
  double _todayDistance = 0;
  int _satelliteCount = 0;
  bool _batteryCharging = false;

  Timer? _durationTimer;
  Duration _totalDuration = Duration.zero;
  DateTime? _timerStartTime;

  late AnimationController _forwardAnimationController;
  Timer? _continuousAnimationTimer;
  LatLng? _lastAnimatedPosition;
  double _metersPerSecond = 0;
  static const int _animationFps = 60;

  @override
  void initState() {
    super.initState();
    _forwardAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60 FPS
    );
    _loadCustomIcon().then((_) {
      _initializeTracking();
    });
    _startDurationTimer();
  }

  void _startContinuousAnimation() {
    _continuousAnimationTimer?.cancel();
    _lastAnimatedPosition = _targetLocation;

    // Calculate meters per second from km/h
    _metersPerSecond = _currentSpeed * (1000 / 3600);

    _continuousAnimationTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _animationFps).round()),
      (timer) {
        if (!mounted ||
            _lastAnimatedPosition == null ||
            _metersPerSecond <= 0) {
          timer.cancel();
          return;
        }

        // Calculate distance to move in this frame
        double distancePerFrame = _metersPerSecond / _animationFps;

        // Convert distance and bearing to lat/lng change
        double bearingRadians = (_currentBearing * pi) / 180;

        // Calculate new position using Haversine formula
        double lat1 = _lastAnimatedPosition!.latitude * pi / 180;
        double lon1 = _lastAnimatedPosition!.longitude * pi / 180;

        // Earth's radius in meters
        const double R = 6378137;

        // Calculate new position
        double lat2 = asin(sin(lat1) * cos(distancePerFrame / R) +
            cos(lat1) * sin(distancePerFrame / R) * cos(bearingRadians));

        double lon2 = lon1 +
            atan2(sin(bearingRadians) * sin(distancePerFrame / R) * cos(lat1),
                cos(distancePerFrame / R) - sin(lat1) * sin(lat2));

        // Convert back to degrees
        double newLat = lat2 * 180 / pi;
        double newLng = lon2 * 180 / pi;

        setState(() {
          _lastAnimatedPosition = LatLng(newLat, newLng);

          if (_customIcon != null) {
            _markers = {
              Marker(
                markerId: const MarkerId('vehicle'),
                position: _lastAnimatedPosition!,
                rotation: _currentBearing,
                icon: _customIcon!,
                flat: true,
                anchor: const Offset(0.5, 0.5),
                infoWindow: InfoWindow(
                  title: widget.deviceName,
                  snippet: 'Speed: ${_currentSpeed.toStringAsFixed(1)} km/h',
                ),
              ),
            };
          }

          if (_followVehicle && _mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: _lastAnimatedPosition!,
                  zoom: 17,
                  bearing: _currentBearing,
                ),
              ),
            );
          }
        });
      },
    );
  }

  void _startDurationTimer() {
    _timerStartTime = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        _totalDuration = DateTime.now().difference(_timerStartTime!);
      });
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    return "$hours:$minutes";
  }

  Future<void> _openInGoogleMaps() async {
    if (_targetLocation == null) return;

    final url =
        'https://www.google.com/maps/search/?api=1&query=${_targetLocation!.latitude},${_targetLocation!.longitude}';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    }
  }

  Future<void> _loadCustomIcon() async {
    try {
      final ByteData data = await rootBundle.load('assets/Yellow.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 48,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (mounted) {
        _customIcon =
            BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading vehicle icon: $e')),
        );
      }
    }
  }

  void _startAnimation() {
    _animationTimer?.cancel();
    _animationProgress = 0;

    _animationTimer = Timer.periodic(
      Duration(milliseconds: (animationUpdateInterval * 1000).toInt()),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _animationProgress += animationUpdateInterval / animationDuration;
          if (_animationProgress >= 1.0) {
            _animationProgress = 1.0;
            timer.cancel();
          }
          _updateMarkerPosition();
        });
      },
    );
  }

  void _updateMarkerPosition() {
    if (_previousLocation == null || _targetLocation == null || !mounted)
      return;

    final interpolatedPosition = _interpolatePosition(
      _previousLocation!,
      _targetLocation!,
      _animationProgress,
    );

    if (_customIcon != null) {
      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('vehicle'),
            position: interpolatedPosition,
            rotation: _currentBearing,
            icon: _customIcon!,
            flat: true,
            anchor: const Offset(0.5, 0.5),
            infoWindow: InfoWindow(
              title: widget.deviceName,
              snippet: 'Speed: ${_currentSpeed.toStringAsFixed(1)} km/h',
            ),
          ),
        };
      });

      if (_followVehicle && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: interpolatedPosition,
              zoom: 17,
              bearing: _currentBearing,
            ),
          ),
        );
      }
    }
  }

  LatLng _interpolatePosition(LatLng start, LatLng end, double progress) {
    final lat = start.latitude + (end.latitude - start.latitude) * progress;
    final lng = start.longitude + (end.longitude - start.longitude) * progress;
    return LatLng(lat, lng);
  }

  void _updatePolylines() {
    if (_targetLocation != null &&
        (_completeRoute.isEmpty || _completeRoute.last != _targetLocation)) {
      _completeRoute.add(_targetLocation!);

      if (_completeRoute.length > 1000) {
        _completeRoute = _completeRoute.sublist(_completeRoute.length - 1000);
      }

      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('complete_route'),
            points: _completeRoute,
            color: Colors.blue.withOpacity(0.7),
            width: 4,
            endCap: Cap.roundCap,
            startCap: Cap.roundCap,
          ),
        };
      });
    }
  }

  Future<void> _initializeTracking() async {
    await _updateLocation();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateLocation(),
    );
  }

  Future<void> _updateLocation() async {
    if (!mounted) return;

    try {
      final locationData = await _trackingProvider.getCurrentLocation(
        int.parse(widget.deviceId),
      );

      _previousLocation = _currentLocation ??
          LatLng(
            locationData['latitude'],
            locationData['longitude'],
          );

      _targetLocation = LatLng(
        locationData['latitude'],
        locationData['longitude'],
      );

      final double speed = locationData['speed'] ?? 0.0;
      final bool ignition = locationData['attributes']?['ignition'] ?? false;

      setState(() {
        _todayDistance =
            locationData['attributes']?['distance']?.toDouble() ?? 0.0;
        _totalDistance =
            (locationData['attributes']?['totalDistance']?.toDouble() ?? 0.0) /
                1000;
        _satelliteCount = locationData['attributes']?['sat'] ?? 0;
        _batteryCharging = locationData['attributes']?['charge'] ?? false;
      });

      final dynamic lastUpdateValue = locationData['lastUpdate'];
      DateTime parsedLastUpdate;

      if (lastUpdateValue is String) {
        parsedLastUpdate = DateTime.parse(lastUpdateValue);
      } else if (lastUpdateValue is DateTime) {
        parsedLastUpdate = lastUpdateValue;
      } else {
        parsedLastUpdate = DateTime.now();
      }

      String address = await _trackingProvider.getAddressFromLatLng(
        locationData['latitude'],
        locationData['longitude'],
      );

      setState(() {
        _currentSpeed = speed;
        _currentBearing = locationData['course']?.toDouble() ?? 0.0;
        _lastUpdate = parsedLastUpdate;
        _ignition = ignition;
        _isMoving = speed > speedThreshold &&
            ignition == true &&
            speed <= overspeedThreshold;
        _currentAddress = address;
      });

      _updatePolylines();
      _startAnimation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating location: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _updateMapType() {
    setState(() {
      if (_isSatelliteEnabled) {
        _currentMapType = MapType.satellite;
      } else if (_isTerrainEnabled) {
        _currentMapType = MapType.terrain;
      } else {
        _currentMapType = MapType.normal;
      }
    });
  }

  @override
  void dispose() {
    _continuousAnimationTimer?.cancel();
    _forwardAnimationController.dispose();
    _durationTimer?.cancel();
    _locationTimer?.cancel();
    _animationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    _minPanelHeight = screenHeight * 0.09;
    _maxPanelHeight = screenHeight * 0.26;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.deviceName,
              style: const TextStyle(
                fontSize: 18.0,
              ),
            ),
            Text(
              _lastUpdate != null
                  ? "Last updated: ${DateFormat('dd/MM/yyyy hh:mm a').format(_lastUpdate!.add(const Duration(hours: 5, minutes: 30)))}"
                  : "Last updated: N/A",
              style: const TextStyle(
                fontSize: 12.0,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Stack(
        children: [
          _targetLocation == null
              ? Center(
                  child: LoadingAnimationWidget.flickr(
                    leftDotColor: Colors.red,
                    rightDotColor: Colors.blue,
                    size: 30,
                  ),
                )
              : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _targetLocation!,
                    zoom: 17,
                    bearing: _currentBearing,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) => _mapController = controller,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  mapType: _currentMapType,
                  compassEnabled: false,
                  rotateGesturesEnabled: true,
                ),
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.map_outlined),
                        onPressed: _openInGoogleMaps,
                        tooltip: 'Open in Google Maps',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.layers),
                        onPressed: () {
                          setState(() {
                            _showMapTypeToggles = !_showMapTypeToggles;
                          });
                        },
                        tooltip: 'Change map type',
                      ),
                    ),
                  ],
                ),
                if (_showMapTypeToggles)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Satellite'),
                            Switch(
                              value: _isSatelliteEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _isSatelliteEnabled = value;
                                  if (value) {
                                    _isTerrainEnabled = false;
                                  }
                                  _updateMapType();
                                });
                              },
                              activeColor: AppColors.primaryColor,
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Terrain'),
                            Switch(
                              value: _isTerrainEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _isTerrainEnabled = value;
                                  if (value) {
                                    _isSatelliteEnabled = false;
                                  }
                                  _updateMapType();
                                });
                              },
                              activeColor: AppColors.primaryColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SlidingUpPanel(
            controller: _panelController,
            color: const ui.Color.fromARGB(214, 255, 255, 255),
            minHeight: _minPanelHeight,
            maxHeight: _maxPanelHeight,
            defaultPanelState: PanelState.OPEN,
            panel: Container(
              child: Column(
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: screenWidth * 0.15,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Address Section
                  Row(
                    children: [
                      SizedBox(
                        height: screenWidth * 0.08,
                        width: screenWidth * 0.08,
                        child: Image.asset("assets/location.png"),
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Expanded(
                        child: Text(
                          _currentAddress,
                          style: TextStyle(
                            fontSize: screenWidth * 0.03,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.start,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const Divider(thickness: 1),

                  // Stats Section
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildResponsiveOdometerSection(screenWidth),
                        _buildResponsiveDistanceSection(screenWidth),
                        _buildResponsiveDurationSection(screenWidth),
                        _buildResponsiveStatusIcons(screenWidth),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveOdometerSection(double screenWidth) {
    double speedPercentage =
        (_currentSpeed / overspeedThreshold).clamp(0.0, 1.0);
    double circleSize = screenWidth * 0.15;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: circleSize,
          width: circleSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: speedPercentage,
                backgroundColor: Colors.orange.shade200,
                color: Colors.green,
                strokeWidth: 4,
              ),
              Text(
                '${_currentSpeed.toStringAsFixed(0)}\nKm/h',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: screenWidth * 0.02,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: screenWidth * 0.02),
        Text(
          _totalDistance.toStringAsFixed(0),
          style: TextStyle(
            fontSize: screenWidth * 0.025,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          'odometer',
          style: TextStyle(
            color: Colors.grey,
            fontSize: screenWidth * 0.025,
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveDistanceSection(double screenWidth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: screenWidth * 0.08,
          width: screenWidth * 0.08,
          child: Image.asset("assets/kilometer.png"),
        ),
        SizedBox(height: screenWidth * 0.02),
        Text(
          'Today Km',
          style: TextStyle(
            color: Colors.grey,
            fontSize: screenWidth * 0.025,
          ),
        ),
        Text(
          '${_todayDistance.toStringAsFixed(0)} km',
          style: TextStyle(
            fontSize: screenWidth * 0.025,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: screenWidth * 0.02),
        Text(
          'From Last Stop',
          style: TextStyle(
            color: Colors.grey,
            fontSize: screenWidth * 0.025,
          ),
        ),
        Text(
          '${(_todayDistance - (_previousLocation != null ? _todayDistance : 0)).toStringAsFixed(1)} km',
          style: TextStyle(
            fontSize: screenWidth * 0.025,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveDurationSection(double screenWidth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: screenWidth * 0.08,
          width: screenWidth * 0.08,
          child: Image.asset("assets/future.png"),
        ),
        SizedBox(height: screenWidth * 0.02),
        Text(
          'Duration',
          style: TextStyle(
            color: Colors.grey,
            fontSize: screenWidth * 0.025,
          ),
        ),
        Text(
          _formatDuration(_totalDuration),
          style: TextStyle(
            fontSize: screenWidth * 0.025,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: screenWidth * 0.02),
      ],
    );
  }

  Widget _buildResponsiveStatusIcons(double screenWidth) {
    double iconSize = screenWidth * 0.045;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.battery_6_bar_rounded,
          color: _batteryCharging ? Colors.green : Colors.orange,
          size: iconSize,
        ),
        SizedBox(height: screenWidth * 0.055),
        Icon(
          Icons.network_cell_rounded,
          color: Colors.green,
          size: iconSize,
        ),
        SizedBox(height: screenWidth * 0.055),
        Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.gps_not_fixed,
              color: _satelliteCount >= 4 ? Colors.green : Colors.orange,
              size: iconSize,
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  _satelliteCount.toString(),
                  style: TextStyle(fontSize: screenWidth * 0.018),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
