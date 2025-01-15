class NetworkCellTower {
  final int? cellId;
  final int? locationAreaCode;
  final int? mobileCountryCode;
  final int? mobileNetworkCode;

  NetworkCellTower({
    this.cellId,
    this.locationAreaCode,
    this.mobileCountryCode,
    this.mobileNetworkCode,
  });

  factory NetworkCellTower.fromJson(Map<String, dynamic> json) {
    return NetworkCellTower(
      cellId: json['cellId'] as int?,
      locationAreaCode: json['locationAreaCode'] as int?,
      mobileCountryCode: json['mobileCountryCode'] as int?,
      mobileNetworkCode: json['mobileNetworkCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'cellId': cellId,
        'locationAreaCode': locationAreaCode,
        'mobileCountryCode': mobileCountryCode,
        'mobileNetworkCode': mobileNetworkCode,
      };
}

class Network {
  final String? radioType;
  final bool? considerIp;
  final List<NetworkCellTower>? cellTowers;

  Network({
    this.radioType,
    this.considerIp,
    this.cellTowers,
  });

  factory Network.fromJson(Map<String, dynamic> json) {
    return Network(
      radioType: json['radioType'] as String?,
      considerIp: json['considerIp'] as bool?,
      cellTowers: (json['cellTowers'] as List?)
          ?.map((e) => NetworkCellTower.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'radioType': radioType,
        'considerIp': considerIp,
        'cellTowers': cellTowers?.map((e) => e.toJson()).toList(),
      };
}

class PositionAttributes {
  final int? sat;
  final bool? ignition;
  final int? status;
  final bool? charge;
  final bool? blocked;
  final double? power;
  final int? rssi;
  final double? distance;
  final double? totalDistance;
  final bool? motion;
  final int? hours;

  PositionAttributes({
    this.sat,
    this.ignition,
    this.status,
    this.charge,
    this.blocked,
    this.power,
    this.rssi,
    this.distance,
    this.totalDistance,
    this.motion,
    this.hours,
  });

  factory PositionAttributes.fromJson(Map<String, dynamic> json) {
    return PositionAttributes(
      sat: json['sat'] as int?,
      ignition: json['ignition'] as bool?,
      status: json['status'] as int?,
      charge: json['charge'] as bool?,
      blocked: json['blocked'] as bool?,
      power: (json['power'] as num?)?.toDouble(),
      rssi: json['rssi'] as int?,
      distance: (json['distance'] as num?)?.toDouble(),
      totalDistance: (json['totalDistance'] as num?)?.toDouble(),
      motion: json['motion'] as bool?,
      hours: json['hours'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'sat': sat,
        'ignition': ignition,
        'status': status,
        'charge': charge,
        'blocked': blocked,
        'power': power,
        'rssi': rssi,
        'distance': distance,
        'totalDistance': totalDistance,
        'motion': motion,
        'hours': hours,
      };
}

class Position {
  final int? id;
  final PositionAttributes? attributes;
  final int? deviceId;
  final String? protocol;
  final DateTime? serverTime;
  final DateTime? deviceTime;
  final DateTime? fixTime;
  final bool? outdated;
  final bool? valid;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? speed;
  final double? course;
  final String? address;
  final double? accuracy;
  final Network? network;
  final List<int>? geofenceIds;

  Position({
    this.id,
    this.attributes,
    this.deviceId,
    this.protocol,
    this.serverTime,
    this.deviceTime,
    this.fixTime,
    this.outdated,
    this.valid,
    this.latitude,
    this.longitude,
    this.altitude,
    this.speed,
    this.course,
    this.address,
    this.accuracy,
    this.network,
    this.geofenceIds,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      id: json['id'] as int?,
      attributes: json['attributes'] != null
          ? PositionAttributes.fromJson(
              json['attributes'] as Map<String, dynamic>)
          : null,
      deviceId: json['deviceId'] as int?,
      protocol: json['protocol'] as String?,
      serverTime: json['serverTime'] != null
          ? DateTime.parse(json['serverTime'] as String)
          : null,
      deviceTime: json['deviceTime'] != null
          ? DateTime.parse(json['deviceTime'] as String)
          : null,
      fixTime: json['fixTime'] != null
          ? DateTime.parse(json['fixTime'] as String)
          : null,
      outdated: json['outdated'] as bool?,
      valid: json['valid'] as bool?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      course: (json['course'] as num?)?.toDouble(),
      address: json['address'] as String?,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      network: json['network'] != null
          ? Network.fromJson(json['network'] as Map<String, dynamic>)
          : null,
      geofenceIds: json['geofenceIds'] != null
          ? (json['geofenceIds'] as List).map((e) => e as int).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'attributes': attributes?.toJson(),
        'deviceId': deviceId,
        'protocol': protocol,
        'serverTime': serverTime?.toIso8601String(),
        'deviceTime': deviceTime?.toIso8601String(),
        'fixTime': fixTime?.toIso8601String(),
        'outdated': outdated,
        'valid': valid,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'speed': speed,
        'course': course,
        'address': address,
        'accuracy': accuracy,
        'network': network?.toJson(),
        'geofenceIds': geofenceIds,
      };
}

class DeviceBranch {
  final int? id;
  final Map<String, dynamic>? attributes;
  final int? groupId;
  final int? calendarId;
  final String? name;
  final String? uniqueId;
  final String? status;
  final DateTime? lastUpdate;
  final int? positionId;
  final String? phone;
  final String? model;
  final String? contact;
  final String? category;
  final bool? disabled;
  final DateTime? expirationTime;

  DeviceBranch({
    this.id,
    this.attributes,
    this.groupId,
    this.calendarId,
    this.name,
    this.uniqueId,
    this.status,
    this.lastUpdate,
    this.positionId,
    this.phone,
    this.model,
    this.contact,
    this.category,
    this.disabled,
    this.expirationTime,
  });

  factory DeviceBranch.fromJson(Map<String, dynamic> json) {
    return DeviceBranch(
      id: json['id'] as int?,
      attributes: json['attributes'] as Map<String, dynamic>?,
      groupId: json['groupId'] as int?,
      calendarId: json['calendarId'] as int?,
      name: json['name'] as String?,
      uniqueId: json['uniqueId'] as String?,
      status: json['status'] as String?,
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.parse(json['lastUpdate'] as String)
          : null,
      positionId: json['positionId'] as int?,
      phone: json['phone'] as String?,
      model: json['model'] as String?,
      contact: json['contact'] as String?,
      category: json['category'] as String?,
      disabled: json['disabled'] as bool?,
      expirationTime: json['expirationTime'] != null
          ? DateTime.parse(json['expirationTime'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'attributes': attributes,
        'groupId': groupId,
        'calendarId': calendarId,
        'name': name,
        'uniqueId': uniqueId,
        'status': status,
        'lastUpdate': lastUpdate?.toIso8601String(),
        'positionId': positionId,
        'phone': phone,
        'model': model,
        'contact': contact,
        'category': category,
        'disabled': disabled,
        'expirationTime': expirationTime?.toIso8601String(),
      };
}
