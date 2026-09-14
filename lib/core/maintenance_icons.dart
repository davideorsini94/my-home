import 'package:flutter/material.dart';

/// One entry of the maintenance icon library.
class MaintenanceIcon {
  const MaintenanceIcon({
    required this.key,
    required this.icon,
    required this.label,
  });

  /// The stable identifier persisted to Firestore.
  ///
  /// Never the icon's codepoint: codepoints move between Flutter releases and
  /// icon tree-shaking keys off them, so a stored codepoint can silently become
  /// a different picture — or none — after an upgrade.
  final String key;

  final IconData icon;
  final String label;
}

const String defaultMaintenanceIconKey = 'generic';

/// The icons offered when creating a maintenance, in the order shown.
///
/// Grouped roughly by domain — heating and climate, water, energy, building,
/// safety, then general — so the picker reads as a list of house systems
/// rather than an alphabetical jumble.
const List<MaintenanceIcon> maintenanceIconLibrary = [
  MaintenanceIcon(
    key: 'boiler',
    icon: Icons.local_fire_department_outlined,
    label: 'Caldaia',
  ),
  MaintenanceIcon(
    key: 'heat_pump',
    icon: Icons.heat_pump_outlined,
    label: 'Pompa di calore',
  ),
  MaintenanceIcon(
    key: 'air_conditioning',
    icon: Icons.ac_unit_outlined,
    label: 'Climatizzatore',
  ),
  MaintenanceIcon(
    key: 'chimney',
    icon: Icons.fireplace_outlined,
    label: 'Camino / canna fumaria',
  ),
  MaintenanceIcon(
    key: 'septic_tank',
    icon: Icons.wc_outlined,
    label: 'Fossa biologica',
  ),
  MaintenanceIcon(
    key: 'plumbing',
    icon: Icons.plumbing_outlined,
    label: 'Impianto idraulico',
  ),
  MaintenanceIcon(
    key: 'water_softener',
    icon: Icons.water_drop_outlined,
    label: 'Addolcitore',
  ),
  MaintenanceIcon(
    key: 'autoclave',
    icon: Icons.water_outlined,
    label: 'Autoclave / pompa acqua',
  ),
  MaintenanceIcon(
    key: 'electrical',
    icon: Icons.electrical_services_outlined,
    label: 'Impianto elettrico',
  ),
  MaintenanceIcon(
    key: 'solar',
    icon: Icons.solar_power_outlined,
    label: 'Pannelli solari / fotovoltaico',
  ),
  MaintenanceIcon(
    key: 'gas',
    icon: Icons.gas_meter_outlined,
    label: 'Impianto gas',
  ),
  MaintenanceIcon(
    key: 'fuel_tank',
    icon: Icons.propane_tank_outlined,
    label: 'Serbatoio GPL / gasolio',
  ),
  MaintenanceIcon(
    key: 'elevator',
    icon: Icons.elevator_outlined,
    label: 'Ascensore',
  ),
  MaintenanceIcon(key: 'garden', icon: Icons.yard_outlined, label: 'Giardino'),
  MaintenanceIcon(key: 'pool', icon: Icons.pool_outlined, label: 'Piscina'),
  MaintenanceIcon(
    key: 'alarm',
    icon: Icons.security_outlined,
    label: 'Allarme / antifurto',
  ),
  MaintenanceIcon(
    key: 'cameras',
    icon: Icons.camera_outdoor_outlined,
    label: 'Videosorveglianza',
  ),
  MaintenanceIcon(
    key: 'extinguisher',
    icon: Icons.fire_extinguisher_outlined,
    label: 'Estintore',
  ),
  MaintenanceIcon(
    key: 'detectors',
    icon: Icons.sensors_outlined,
    label: 'Rilevatori fumo / gas',
  ),
  MaintenanceIcon(
    key: 'roof',
    icon: Icons.roofing_outlined,
    label: 'Tetto / grondaie',
  ),
  MaintenanceIcon(
    key: 'windows',
    icon: Icons.window_outlined,
    label: 'Serramenti / zanzariere',
  ),
  MaintenanceIcon(
    key: 'blinds',
    icon: Icons.blinds_outlined,
    label: 'Tende / tapparelle',
  ),
  MaintenanceIcon(
    key: 'gate',
    icon: Icons.fence_outlined,
    label: 'Cancello elettrico / recinzione',
  ),
  MaintenanceIcon(
    key: 'garage',
    icon: Icons.garage_outlined,
    label: 'Garage / basculante',
  ),
  MaintenanceIcon(
    key: 'appliances',
    icon: Icons.kitchen_outlined,
    label: 'Elettrodomestici',
  ),
  MaintenanceIcon(
    key: 'laundry',
    icon: Icons.local_laundry_service_outlined,
    label: 'Lavatrice / asciugatrice',
  ),
  MaintenanceIcon(
    key: 'pest_control',
    icon: Icons.pest_control_outlined,
    label: 'Disinfestazione / derattizzazione',
  ),
  MaintenanceIcon(
    key: 'cleaning',
    icon: Icons.cleaning_services_outlined,
    label: 'Pulizie periodiche',
  ),
  MaintenanceIcon(
    key: 'car',
    icon: Icons.directions_car_outlined,
    label: 'Auto (revisione, tagliando)',
  ),
  MaintenanceIcon(
    key: defaultMaintenanceIconKey,
    icon: Icons.build_outlined,
    label: 'Generica',
  ),
];

final Map<String, MaintenanceIcon> _byKey = {
  for (final entry in maintenanceIconLibrary) entry.key: entry,
};

/// The library entry for [key], falling back to the generic one.
///
/// A key written by a newer version of the app must not break an older client:
/// it renders as the generic wrench rather than crashing or showing nothing.
MaintenanceIcon maintenanceIconFor(String? key) =>
    _byKey[key] ?? _byKey[defaultMaintenanceIconKey]!;

String maintenanceIconLabel(String? key) => maintenanceIconFor(key).label;
