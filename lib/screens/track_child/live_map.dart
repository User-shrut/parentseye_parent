import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:parentseye_parent/constants/api_constants.dart';
import 'package:parentseye_parent/constants/app_colors.dart';
import 'package:parentseye_parent/models/geofencing_model.dart';
import 'package:parentseye_parent/models/parent_student_model.dart.dart';
import 'package:parentseye_parent/models/positions_model.dart';
import 'package:parentseye_parent/provider/auth_provider.dart';
import 'package:parentseye_parent/provider/live_tracking_provider.dart';
import 'package:provider/provider.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../provider/geofences_provider.dart';

class TrackingScreen extends StatefulWidget {
  final int deviceId;
  final StudentDetails studentDetails;

  TrackingScreen({
    Key? key,
    required this.deviceId,
    required this.studentDetails,
  }) : super(key: key);

  @override
  _TrackingScreenState createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _customIcon;
  String _currentIconPath = 'assets/Yellow.png';

  String _currentAddress = "Fetching address...";
  double _currentCourse = 0.0;
  String _nearestStop = "Calculating...";
  String _eta = "Calculating...";
  bool _isActive = true;
  bool isPanelOpen = false;

  Color _currentBorderColor = Colors.yellow;
  final List<LatLng> _animatedPolylineCoordinates = [];
  String _lastUpdateTime = "Fetching...";

  Timer? _updateTimer;
  bool _mounted = true;
  final List<LatLng> _journeyPolylineCoordinates = [];
  bool _isFirstPosition = true;

  MapType _currentMapType = MapType.normal;
  bool _showMapTypeToggles = false;
  bool _isSatelliteEnabled = false;
  bool _isTerrainEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final trackingProvider =
          Provider.of<TrackingProvider>(context, listen: false);
      final geofenceProvider =
          Provider.of<GeofenceProvider>(context, listen: false);
      await trackingProvider.fetchDevice(widget.studentDetails);
      await geofenceProvider.fetchGeofences(widget.deviceId.toString());

      if (mounted) {
        trackingProvider.startTracking(widget.deviceId.toString());
      }
    });
    _startPositionListener();
    _fetchLastUpdate();
    _updateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_mounted) {
        _fetchLastUpdate();
      }
    });
  }

//----------------------------------------------------------------------------------//
  /// NOTE: THIS API IS FETCHED IN THIS UI SCREEN IN FRUSTRATION TO LEAVE OFFICE TO GO HOME EARLY, I KNOW IT IS NOT THE BEST CODING PRACTICE ///
  final String _username = 'schoolmaster';
  final String _password = '123456';
  String _basicAuth() {
    String credentials = '$_username:$_password';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  Future<void> _fetchLastUpdate() async {
    if (!_mounted) return;

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.devicesUrl}?id=${widget.deviceId}'),
        headers: {'Authorization': _basicAuth()},
      );

      if (!_mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final String utcTimeString = data[0]['lastUpdate'];
          final DateTime utcTime = DateTime.parse(utcTimeString);
          final DateTime indianTime =
              utcTime.add(const Duration(hours: 5, minutes: 30));
          final String formattedDateTime =
              DateFormat('hh:mm a, dd MMM yyyy').format(indianTime);

          if (_mounted) {
            setState(() {
              _lastUpdateTime = formattedDateTime;
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching last update: $e');
      if (_mounted) {
        setState(() {
          _lastUpdateTime = 'Update failed';
        });
      }
    }
  }
//----------------------------------------------------------------------------------//

  Future<void> _launchCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      throw 'Could not launch $launchUri';
    }
  }

  void _loadCustomIcon(String iconPath) async {
    if (!mounted) return;

    final ByteData data = await DefaultAssetBundle.of(context).load(iconPath);
    if (!_isActive) return;

    final ui.Codec codec = await ui
        .instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 48);
    if (!_isActive) return;

    final ui.FrameInfo fi = await codec.getNextFrame();
    if (!_isActive) return;

    final ByteData? byteData =
        await fi.image.toByteData(format: ui.ImageByteFormat.png);
    if (!_isActive) return;

    final Uint8List resizedBytes = byteData!.buffer.asUint8List();

    if (mounted && _isActive) {
      setState(() {
        _customIcon = BitmapDescriptor.fromBytes(resizedBytes);
      });
    }
  }

  void _updateIconAndBorderColor(PositionsModel lastPosition) {
    Color newBorderColor;
    if (lastPosition.speed >= 5 &&
            lastPosition.attributes['ignition'] == true ||
        false) {
      _currentIconPath = 'assets/Green.png';
      newBorderColor = Colors.green;
    } else if (lastPosition.speed <= 1 &&
        lastPosition.attributes['ignition'] == false) {
      _currentIconPath = 'assets/Red.png';
      newBorderColor = Colors.red;
    } else if (lastPosition.speed == 0 &&
        lastPosition.attributes['ignition'] == true) {
      _currentIconPath = 'assets/Yellow.png';
      newBorderColor = Colors.yellow;
    } else {
      _currentIconPath = 'assets/Red.png';
      newBorderColor = Colors.red;
    }

    _loadCustomIcon(_currentIconPath);
    setState(() {
      _currentBorderColor = newBorderColor;
    });
  }

  void _calculateNearestStopAndETA() {
    final trackingProvider =
        Provider.of<TrackingProvider>(context, listen: false);
    final geofenceProvider =
        Provider.of<GeofenceProvider>(context, listen: false);

    if (trackingProvider.positions.isEmpty ||
        geofenceProvider.geofences.isEmpty) {
      return;
    }

    PositionsModel currentPosition = trackingProvider.positions.last;
    LatLng currentLatLng =
        LatLng(currentPosition.latitude, currentPosition.longitude);
    Geofence? nearestGeofence;
    double nearestDistance = double.infinity;

    for (var geofence in geofenceProvider.geofences) {
      double distance = _distanceBetween(currentLatLng, geofence.center);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestGeofence = geofence;
      }
    }

    setState(() {
      if (nearestGeofence != null) {
        _nearestStop = nearestGeofence.name;

        if (currentPosition.attributes['ignition'] == false &&
            currentPosition.speed == 0) {
          _eta = "M 00 : S 00";
        } else {
          double etaInHours = nearestDistance / 30;
          int totalSeconds = (etaInHours * 3600).round();
          int minutes = totalSeconds ~/ 60;
          int seconds = totalSeconds % 60;
          _eta =
              "M ${minutes.toString().padLeft(2, '0')} : S ${seconds.toString().padLeft(2, '0')}";
        }
      } else {
        _nearestStop = "No stop found";
        _eta = "N/A";
      }
    });
  }

  void _startPositionListener() {
    Provider.of<TrackingProvider>(context, listen: false).addListener(() {
      if (mounted) {
        final provider = Provider.of<TrackingProvider>(context, listen: false);

        if (provider.currentAnimatedPosition != null) {
          _updateAnimatedPolyline(provider.currentAnimatedPosition!);

          if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: provider.currentAnimatedPosition!,
                  zoom: 18,
                  bearing: provider.currentAnimatedBearing,
                ),
              ),
            );
          }

          _getAddressFromLatLng(provider.currentAnimatedPosition!);
          setState(() {
            _currentCourse = provider.currentAnimatedBearing;
          });
          _calculateNearestStopAndETA();

          if (provider.positions.isNotEmpty) {
            _updateIconAndBorderColor(provider.positions.last);
          }
        }
      }
    });
  }

  void _updateAnimatedPolyline(LatLng newPosition) {
    if (mounted) {
      setState(() {
        if (_isFirstPosition) {
          _journeyPolylineCoordinates.add(newPosition);
          _isFirstPosition = false;
          return;
        }
        if (_journeyPolylineCoordinates.isEmpty ||
            _journeyPolylineCoordinates.last != newPosition) {
          double distance = _distanceBetweenPoints(
              _journeyPolylineCoordinates.last, newPosition);
          if (distance <= 500) {
            _journeyPolylineCoordinates.add(newPosition);
          }
        }
      });
    }
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];

      if (mounted) {
        setState(() {
          _currentAddress =
              "${place.street},${place.subLocality}, ${place.locality}, ${place.postalCode}, ${place.country}";
        });
      }
    } catch (e) {
      print(e);
    }
  }

  double _calculatePanelContentHeight(BuildContext context) {
    double addressRowHeight = 80.0;
    double etaRowHeight = 60.0;
    double callButtonsRowHeight = 60.0;
    double contentHeight =
        addressRowHeight + etaRowHeight + callButtonsRowHeight;
    contentHeight += 20.0;
    contentHeight += 16.0;

    return contentHeight;
  }

  Future<void> _openInGoogleMaps() async {
    final trackingProvider =
        Provider.of<TrackingProvider>(context, listen: false);
    if (trackingProvider.currentAnimatedPosition == null) return;

    final url =
        'https://www.google.com/maps/search/?api=1&query=${trackingProvider.currentAnimatedPosition!.latitude},${trackingProvider.currentAnimatedPosition!.longitude}';
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
    _mounted = false;
    _updateTimer?.cancel();
    _isActive = false;
    _journeyPolylineCoordinates.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geofenceProvider = Provider.of<GeofenceProvider>(context);
    final geofences = geofenceProvider.geofences;
    final authProvider = Provider.of<AuthProvider>(context);
    final bool fullAccess = authProvider.hasFullAccess;
    final trackingProvider = Provider.of<TrackingProvider>(context);

    double panelContentHeight = _calculatePanelContentHeight(context);
    double maxPanelHeight = panelContentHeight + 20.0;
    double minPanelHeight = 115.0;

    Set<Circle> circles = geofences.map((geofence) {
      return Circle(
        circleId: CircleId(geofence.id),
        center: geofence.center,
        radius: geofence.radius,
        fillColor: AppColors.primaryColor.withOpacity(0.5),
        strokeColor: AppColors.primaryColor,
        strokeWidth: 2,
      );
    }).toSet();

    return Scaffold(
      appBar: fullAccess == false
          ? AppBar(
              backgroundColor: AppColors.primaryColor,
              elevation: 0,
              title: Text(
                widget.studentDetails.deviceName,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              centerTitle: false,
            )
          : null,
      body: Stack(
        children: [
          Consumer<TrackingProvider>(
            builder: (context, provider, child) {
              if (provider.positions.isEmpty ||
                  provider.currentAnimatedPosition == null) {
                return Center(
                  child: LoadingAnimationWidget.flickr(
                    leftDotColor: Colors.red,
                    rightDotColor: Colors.blue,
                    size: 30,
                  ),
                );
              }

              return GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: provider.currentAnimatedPosition!,
                  zoom: 18.0,
                ),
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('carPath'),
                    color: Colors.blue,
                    width: 3,
                    points: _journeyPolylineCoordinates,
                    endCap: Cap.roundCap,
                    startCap: Cap.roundCap,
                    geodesic: true,
                  ),
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('car'),
                    position: provider.currentAnimatedPosition!,
                    icon: _customIcon ?? BitmapDescriptor.defaultMarker,
                    rotation: provider.currentAnimatedBearing,
                    anchor: const Offset(0.5, 0.5),
                    flat: true,
                  ),
                },
                circles: circles,
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                compassEnabled: false,
                mapType: _currentMapType,
                myLocationEnabled: false,
                zoomControlsEnabled: false,
              );
            },
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
          Positioned(
            left: 10,
            top: 16,
            child: SizedBox(
              width: 55,
              child: Card(
                color: const ui.Color.fromARGB(176, 255, 255, 255),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
                        height: 50,
                        width: 50,
                        decoration: BoxDecoration(boxShadow: const [
                          BoxShadow(
                            color: Colors.grey,
                            offset: Offset(2, 0),
                            blurRadius: 4,
                            spreadRadius: 0,
                          ),
                        ], color: Colors.white, shape: BoxShape.circle),
                        child: Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.gps_not_fixed,
                                color: Colors.green,
                              ),
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.center,
                                  //attributes.sat
                                  child: Text(
                                    "12",
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                          height: 50,
                          width: 50,
                          decoration: BoxDecoration(boxShadow: const [
                            BoxShadow(
                              color: Colors.grey,
                              offset: Offset(2, 0),
                              blurRadius: 4,
                              spreadRadius: 0,
                            ),
                          ], color: Colors.white, shape: BoxShape.circle),
                          child: Icon(
                            Icons.battery_6_bar,
                            size: 15.0,
                            color: Colors.green,
                          )),
                      Container(
                          height: 50,
                          width: 50,
                          decoration: const BoxDecoration(boxShadow: [
                            BoxShadow(
                              color: Colors.grey,
                              offset: Offset(2, 0),
                              blurRadius: 4,
                              spreadRadius: 0,
                            ),
                          ], color: Colors.white, shape: BoxShape.circle),
                          child:
                              Icon(Icons.key, size: 15.0, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SlidingUpPanel(
            maxHeight: fullAccess == true ? maxPanelHeight : panelContentHeight,
            minHeight: minPanelHeight,
            color: Colors.transparent,
            defaultPanelState: PanelState.OPEN,
            onPanelSlide: (double pos) => setState(() {
              isPanelOpen = pos > 0.5;
            }),
            panel: Stack(
              alignment: Alignment.topCenter,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: panelContentHeight,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 10.0,
                    ),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      color: Colors.white,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: _currentBorderColor,
                              width: 5.0,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          title: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Consumer<TrackingProvider>(
                                builder: (context, provider, child) {
                                  return buildRowItem1(_currentAddress);
                                },
                              ),
                              if (fullAccess == true) buildDivider1(),
                              if (fullAccess == true) buildRowItem2(),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: buildDivider(),
                              ),
                              buildRowItem3(
                                'Call Driver',
                                "Call School",
                                Icons.call,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 5,
                  child: Icon(
                    isPanelOpen
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 35,
                    color: AppColors.primaryColor,
                  ),
                ),
              ],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(18.0)),
          ),
        ],
      ),
    );
  }

  Widget buildDivider() {
    return const Divider(
      color: Colors.grey,
      height: 8.0,
      thickness: 0.5,
    );
  }

  Widget buildDivider1() {
    return const Padding(
      padding: EdgeInsets.only(left: 80.0),
      child: Divider(
        color: Colors.grey,
        height: 8.0,
        thickness: 0.5,
      ),
    );
  }

  Widget buildRowItem3(String text, String text3, IconData iconData) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        GestureDetector(
          onTap: () => _launchCall(widget.studentDetails.driverMobile),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.yellow.shade600,
            ),
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              iconData,
              color: Colors.black,
            ),
          ),
        ),
        Text(
          text,
          style: const TextStyle(fontSize: 16.0),
        ),
        const SizedBox(width: 8.0),
        GestureDetector(
          onTap: () => _launchCall(widget.studentDetails.schoolMobile),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.yellow.shade600,
            ),
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              iconData,
              color: Colors.black,
            ),
          ),
        ),
        Text(
          text3,
          style: const TextStyle(fontSize: 16.0),
        ),
      ],
    );
  }

  Widget buildRowItem2() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 8.0),
        Text(
          "ETA: $_eta",
          style:
              GoogleFonts.poppins(fontSize: 20.0, fontWeight: FontWeight.w500),
        ),
        const SizedBox(
          width: 6,
        ),
        Text(
          "Nearest Stop: $_nearestStop",
          style: TextStyle(
            fontSize: 14.0,
            color: Colors.yellow.shade900,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget buildRowItem1(String title) {
    return Consumer2<TrackingProvider, AuthProvider>(
      builder: (context, trackingProvider, authProvider, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 80,
              width: 80,
              child: Image.asset("assets/school_bus_new.png"),
            ),
            const SizedBox(width: 18.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 15.0),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    "Last Updated: $_lastUpdateTime",
                    style: TextStyle(
                      fontSize: 12.0,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  LatLng _calculateGeofenceCenter(List<LatLng> points) {
    double latitude = 0;
    double longitude = 0;

    for (var point in points) {
      latitude += point.latitude;
      longitude += point.longitude;
    }

    return LatLng(latitude / points.length, longitude / points.length);
  }

  double _calculateGeofenceRadius(List<LatLng> points) {
    LatLng center = _calculateGeofenceCenter(points);
    double maxDistance = 0;

    for (var point in points) {
      double distance = _distanceBetween(center, point);
      if (distance > maxDistance) {
        maxDistance = distance;
      }
    }

    return maxDistance * 1000;
  }

  double _distanceBetween(LatLng start, LatLng end) {
    var earthRadiusKm = 6371;

    var dLat = _degreesToRadians(end.latitude - start.latitude);
    var dLng = _degreesToRadians(end.longitude - start.longitude);

    var a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(start.latitude)) *
            cos(_degreesToRadians(end.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  double _distanceBetweenPoints(LatLng start, LatLng end) {
    var earthRadiusKm = 6371.0;

    var dLat = _degreesToRadians(end.latitude - start.latitude);
    var dLng = _degreesToRadians(end.longitude - start.longitude);

    var a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(start.latitude)) *
            cos(_degreesToRadians(end.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    var c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c * 1000;
  }
}
