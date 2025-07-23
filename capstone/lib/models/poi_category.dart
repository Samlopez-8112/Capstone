enum PoiCategory {
  hospital,
  gasStation,
  police,
  carRepair;

  String get iconPath {
    switch (this) {
      case PoiCategory.hospital:
        return 'assets/icon/hospital.png';
      case PoiCategory.gasStation:
        return 'assets/icon/gas.png';
      case PoiCategory.police:
        return 'assets/icon/police.png';
      case PoiCategory.carRepair:
        return 'assets/icon/mechanic.png';
    }
  }

  String get label {
    switch (this) {
      case PoiCategory.hospital:
        return 'Hospital';
      case PoiCategory.gasStation:
        return 'Gas Station';
      case PoiCategory.police:
        return 'Police Station';
      case PoiCategory.carRepair:
        return 'Mechanic';
    }
  }

  String get apiValue {
    switch (this) {
      case PoiCategory.hospital:
        return 'hospital';
      case PoiCategory.gasStation:
        return 'gas_station';
      case PoiCategory.police:
        return 'police';
      case PoiCategory.carRepair:
        return 'car_repair';
    }
  }
}
