class DeviceBranchLogin {
  final String deviceId;
  final String actualDeviceId;
  final String deviceName;

  DeviceBranchLogin({
    required this.deviceId,
    required this.actualDeviceId,
    required this.deviceName,
  });

  factory DeviceBranchLogin.fromJson(Map<String, dynamic> json) {
    return DeviceBranchLogin(
      deviceId: json['deviceId'] ?? '',
      actualDeviceId: json['actualDeviceId'] ?? '',
      deviceName: json['deviceName'] ?? '',
    );
  }
}
