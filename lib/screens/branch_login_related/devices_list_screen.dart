import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:parentseye_parent/constants/app_colors.dart';
import 'package:parentseye_parent/models/branch_login_related/branch_login_devices_model.dart';
import 'package:parentseye_parent/provider/auth_provider.dart';
import 'package:parentseye_parent/provider/branch_login_related/branch_login_devices_provider.dart';
import 'package:parentseye_parent/provider/branch_login_related/branch_tracking_provider.dart';
import 'package:parentseye_parent/screens/about_us.dart';
import 'package:parentseye_parent/screens/branch_login_related/branch_devices_live_map.dart';
import 'package:parentseye_parent/screens/help_support.dart';
import 'package:provider/provider.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({Key? key}) : super(key: key);

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'All';
  late VehicleTrackingProvider _trackingProvider;
  bool _showSearchBar = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final devicesProvider =
          Provider.of<DeviceBranchLoginProvider>(context, listen: false);
      _trackingProvider =
          Provider.of<VehicleTrackingProvider>(context, listen: false);

      if (authProvider.token != null) {
        devicesProvider.fetchDevices(authProvider.token!).then((_) {
          final deviceIds = devicesProvider.devices
              .map((device) => int.parse(device.deviceId))
              .toList();
          _trackingProvider.startPeriodicUpdates(deviceIds);
        });
      }
    });
  }

  List<DeviceBranchLogin> _filterDevicesByStatus(
    List<DeviceBranchLogin> devices,
    VehicleTrackingProvider trackingProvider,
  ) {
    if (_selectedStatus == 'All') return devices;

    return devices.where((device) {
      final deviceId = int.parse(device.deviceId);
      final deviceData = trackingProvider.getDeviceData(deviceId);
      if (deviceData == null) {
        return _selectedStatus == 'Inactive';
      }

      final double speed = deviceData['speed'] ?? 0.0;
      final bool ignition = deviceData['attributes']?['ignition'] ?? false;
      final String status = deviceData['status'] ?? '';
      final int positionId = deviceData['positionId'] ?? 0;
      final DateTime? lastUpdate = deviceData['lastUpdate'];

      const speedThreshold = 2.0;

      switch (_selectedStatus) {
        case 'Running':
          return speed > speedThreshold && ignition == true && speed <= 60;
        case 'Stop':
          return speed < speedThreshold && ignition == false;
        case 'Idle':
          return speed < speedThreshold && ignition == true;
        case 'Online':
          return status == 'online' || positionId != 0;
        case 'Overspeed':
          return speed > 60 && ignition == true;
        case 'Inactive':
          return status == 'offline' && positionId == 0 && lastUpdate == null;
        default:
          return true;
      }
    }).toList();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _trackingProvider.stopPeriodicUpdates();
    _refreshController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<DeviceBranchLogin> _getFilteredDevices(
    List<DeviceBranchLogin> devices,
    VehicleTrackingProvider trackingProvider,
  ) {
    var statusFilteredDevices =
        _filterDevicesByStatus(devices, trackingProvider);

    if (_searchQuery.isEmpty) {
      return statusFilteredDevices;
    }

    return statusFilteredDevices.where((device) {
      final searchLower = _searchQuery.toLowerCase();
      final deviceNameMatch =
          device.deviceName.toLowerCase().contains(searchLower);

      return deviceNameMatch;
    }).toList();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (!_showSearchBar) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryColor,
      elevation: 4,
      leading: _showSearchBar
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: _toggleSearchBar,
            )
          : Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.black),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
      title: _showSearchBar
          ? TextField(
              controller: _searchController,
              cursorColor: Colors.black,
              autofocus: true,
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'Search buses...',
                hintStyle: GoogleFonts.poppins(
                  color: Colors.black54,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.black54),
                        onPressed: () {
                          _searchController.clear();
                        },
                      ),
                  ],
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            )
          : Text(
              'Dashboard',
              style: GoogleFonts.poppins(
                color: AppColors.textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
      actions: [
        IconButton(
          icon: Icon(
            _showSearchBar ? Icons.clear : Icons.search,
            color: Colors.black,
          ),
          onPressed: _toggleSearchBar,
        ),
      ],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(16),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final authProvider = Provider.of<AuthProvider>(context);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primaryColor),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person,
                      size: 50, color: AppColors.primaryColor),
                ),
                const SizedBox(height: 10),
                Text(
                  authProvider.loginType == 'branch'
                      ? authProvider.branchData!.branchName
                      : '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ),
          _buildTile(
            icon: Icons.help,
            title: 'Help & Support',
            subtitle: 'Get assistance and FAQs',
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const HelpAndSupportScreen()));
            },
          ),
          _buildTile(
            icon: Icons.info,
            title: 'About',
            subtitle: 'Version and app details',
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AboutUsScreen()));
            },
          ),
          _buildTile(
            icon: Icons.info,
            title: 'Logout',
            subtitle: 'Go back to Login page',
            onTap: () {
              authProvider.logout(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          buildStatusCircles(context),
          Expanded(
            child: SmartRefresher(
              controller: _refreshController,
              onRefresh: () async {
                final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                final devicesProvider = Provider.of<DeviceBranchLoginProvider>(
                    context,
                    listen: false);
                if (authProvider.token != null) {
                  await devicesProvider.fetchDevices(authProvider.token!);
                }
                _refreshController.refreshCompleted();
              },
              child:
                  Consumer2<DeviceBranchLoginProvider, VehicleTrackingProvider>(
                builder: (context, devicesProvider, trackingProvider, _) {
                  final filteredDevices = _getFilteredDevices(
                    devicesProvider.devices,
                    trackingProvider,
                  );

                  if (filteredDevices.isEmpty) {
                    return Center(
                      child: _searchQuery.isEmpty
                          ? LoadingAnimationWidget.flickr(
                              leftDotColor: Colors.red,
                              rightDotColor: Colors.blue,
                              size: 30,
                            )
                          : Text(
                              'No devices found for "${_searchQuery}"',
                              style: GoogleFonts.poppins(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredDevices.length,
                    itemBuilder: (context, index) =>
                        CompactDeviceCard(device: filteredDevices[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStatusCircles(BuildContext context) {
    return Consumer2<DeviceBranchLoginProvider, VehicleTrackingProvider>(
      builder: (context, devicesProvider, trackingProvider, _) {
        final counter = DeviceStatusCounter();
        counter.calculateCounts(devicesProvider.devices, trackingProvider);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          height: 80,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _buildStatusCircle(
                    Colors.blue,
                    'All',
                    counter.all,
                    onTap: () => setState(() => _selectedStatus = 'All'),
                    isSelected: _selectedStatus == 'All',
                  ),
                  const SizedBox(width: 16),
                  _buildStatusCircle(
                    Colors.green,
                    'Running',
                    counter.running,
                    onTap: () => setState(() => _selectedStatus = 'Running'),
                    isSelected: _selectedStatus == 'Running',
                  ),
                  const SizedBox(width: 16),
                  _buildStatusCircle(
                    Colors.red,
                    'Stop',
                    counter.stopped,
                    onTap: () => setState(() => _selectedStatus = 'Stop'),
                    isSelected: _selectedStatus == 'Stop',
                  ),
                  const SizedBox(width: 16),
                  _buildStatusCircle(
                    Colors.amber,
                    'Idle',
                    counter.idle,
                    onTap: () => setState(() => _selectedStatus = 'Idle'),
                    isSelected: _selectedStatus == 'Idle',
                  ),
                  const SizedBox(width: 16),
                  _buildStatusCircle(
                    Colors.orange,
                    'Overspeed',
                    counter.overspeed,
                    onTap: () => setState(() => _selectedStatus = 'Overspeed'),
                    isSelected: _selectedStatus == 'Overspeed',
                  ),
                  const SizedBox(width: 16),
                  _buildStatusCircle(
                    Colors.grey,
                    'Offline',
                    counter.inactive,
                    onTap: () => setState(() => _selectedStatus = 'Inactive'),
                    isSelected: _selectedStatus == 'Inactive',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCircle(
    Color color,
    String label,
    int count, {
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 50,
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                count.toString(),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildTile({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primaryColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
      tileColor: AppColors.tileColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
    ),
  );
}

class CompactDeviceCard extends StatelessWidget {
  final dynamic device;

  const CompactDeviceCard({Key? key, required this.device}) : super(key: key);

  String formatLastUpdated(DateTime? dateTime) {
    if (dateTime == null) return 'Loading...';
    final indianTime = dateTime.add(const Duration(hours: 5, minutes: 30));
    return DateFormat('dd/MM/yyyy\nhh:mm a').format(indianTime);
  }

  Widget _buildMetricRow(String label, String value, Color dotColor) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.grey.shade700,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Container(
          height: 5,
          width: 5,
          color: dotColor,
        ),
        const SizedBox(width: 5),
        SizedBox(
          width: 60,
          child: Text(
            value,
            style: GoogleFonts.poppins(
              color: Colors.black,
              fontSize: 8,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VehicleTrackingProvider>(
      builder: (context, trackingProvider, _) {
        final deviceData =
            trackingProvider.getDeviceData(int.parse(device.deviceId));
        final bool isLoading = deviceData == null;
        final bool isDeviceInactive = isLoading ||
            (deviceData['status'] == 'offline' &&
                deviceData['positionId'] == 0 &&
                deviceData['lastUpdate'] == null);
        final bool ignition = deviceData?['attributes']?['ignition'] ?? false;
        final double speed = deviceData?['speed'] ?? 0.0;
        final double distance = deviceData?['attributes']?['distance'] ?? 0.0;
        final sat = deviceData?['attributes']?['sat'] ?? 0.0;
        final bool charge = deviceData?['attributes']?['charge'] ?? false;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => LiveTrackingScreen(
                  deviceId: device.deviceId,
                  deviceName: device.deviceName,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    spreadRadius: 1,
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header section
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.04,
                    child: Container(
                      color: AppColors.primaryColor,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            flex: 3,
                            child: Container(
                              decoration: BoxDecoration(
                                  color: AppColors.primaryColor,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text(
                                device.deviceName,
                                style: GoogleFonts.sansita(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textColor,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Content section
                  Padding(
                    padding: const EdgeInsets.only(left: 0, top: 10, bottom: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 100,
                                width: 150,
                                child: Center(
                                  child: Image.asset(
                                    'assets/school_bus_new.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Column(
                                children: [
                                  _buildMetricRow(
                                      "Last Updated",
                                      formatLastUpdated(
                                          deviceData?['lastUpdate']),
                                      Colors.black),
                                  const SizedBox(height: 10),
                                  _buildMetricRow(
                                    "Status",
                                    isDeviceInactive ? "Offline" : "Online",
                                    isDeviceInactive
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildMetricRow(
                                      "Todays KM",
                                      distance.toStringAsFixed(0),
                                      Colors.orange),
                                  const SizedBox(height: 10),
                                  _buildMetricRow(
                                    "Ignition",
                                    ignition ? "ON" : "OFF",
                                    ignition ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildMetricRow(
                                    "Speed",
                                    "${speed.toStringAsFixed(0)} km/h",
                                    speed > 60 ? Colors.red : Colors.green,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  charge
                                      ? Icon(
                                          Icons.battery_6_bar_rounded,
                                          color: Colors.green,
                                          size: 18,
                                        )
                                      : Icon(
                                          Icons.battery_2_bar_rounded,
                                          color: Colors.red,
                                          size: 18,
                                        ),
                                  const SizedBox(height: 22),
                                  Icon(
                                    Icons.network_cell_rounded,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                  const SizedBox(height: 22),
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(
                                        Icons.gps_not_fixed,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: Text(
                                            sat.toStringAsFixed(0),
                                            style: TextStyle(fontSize: 7),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                ],
                              )
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 10, bottom: 10, top: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: Colors.grey,
                                size: 15,
                              ),
                              Expanded(
                                child: Text(
                                  isLoading
                                      ? 'Fetching address...'
                                      : deviceData['address'] ??
                                          'Address unavailable',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class DeviceStatusCounter {
  int all = 0;
  int running = 0;
  int stopped = 0;
  int idle = 0;
  int online = 0;
  int overspeed = 0;
  int inactive = 0;

  void calculateCounts(List<DeviceBranchLogin> devices,
      VehicleTrackingProvider trackingProvider) {
    all = devices.length;
    const speedThreshold = 2.0;

    for (var device in devices) {
      final deviceId = int.parse(device.deviceId);
      final deviceData = trackingProvider.getDeviceData(deviceId);

      if (deviceData == null) {
        inactive++;
        continue;
      }

      final speed = deviceData['speed'] as double? ?? 0.0;
      final ignition = deviceData['attributes']?['ignition'] as bool? ?? false;
      final status = deviceData['status'] as String? ?? '';
      final positionId = deviceData['positionId'] as int? ?? 0;
      final lastUpdate = deviceData['lastUpdate'] as DateTime?;

      if (speed > speedThreshold && ignition == true && speed <= 60) {
        running++;
      }

      if (speed < speedThreshold && ignition == false) {
        stopped++;
      }

      if (speed < speedThreshold && ignition == true) {
        idle++;
      }

      if (status == 'online' || positionId != 0) {
        online++;
      }

      if (speed > 60 && ignition == true) {
        overspeed++;
      }

      if (status == 'offline' && positionId == 0 && lastUpdate == null) {
        inactive++;
      }
    }
  }
}
