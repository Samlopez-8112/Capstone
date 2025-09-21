// AI assisted in creation of mapping keywords to crime categories
// this utility is used in map_page under _renderFilteredCrimes()

enum CrimeCategory { violent, theft, vehicle, property, drug, other }

/// Returns one or more categories based on the offense *text*.
/// Keywords can be manually input later if any discrepancies are discovered
Set<CrimeCategory> categoriesForOffense(String offense) {
  final o = offense.toLowerCase();

  bool any(Iterable<String> kws) => kws.any((k) => o.contains(k));

  // Keywords (add new ones to the list if any slip through filters)
  const violentKW = [
    'homicide','murder','manslaughter','assault','aggravated assault',
    'battery','robbery','carjacking','kidnapping','rape','sexual',
    'domestic violence','strangulation',
  ];

  const theftKW = [
    'larceny','theft','shoplifting','pickpocket','pocket-picking',
    'purse snatching','stolen property', 'larceny/theft' // could be property too
  ];

  const vehicleKW = [
    'motor vehicle theft','mvt','auto theft','stolen vehicle',
    'theft from motor vehicle','theft from vehicle','vehicle break-in',
    'auto burglary','car prowl','carjacking',
  ];

  const propertyKW = [
    'burglary','b&e','breaking and entering','arson','vandalism',
    'property damage','criminal mischief','trespass','stolen property',
  ];

  const drugKW = [
    'drug','narcotic','controlled substance','marijuana','cannabis',
    'meth','methamphetamine','cocaine','heroin','fentanyl','opioid',
    'paraphernalia',
  ];

  final out = <CrimeCategory>{};

  if (any(violentKW)) out.add(CrimeCategory.violent);
  if (any(theftKW)) out.add(CrimeCategory.theft);
  if (any(vehicleKW)) out.add(CrimeCategory.vehicle);
  if (any(propertyKW)) out.add(CrimeCategory.property);
  if (any(drugKW)) out.add(CrimeCategory.drug);

  // Special case: carjacking is both violent + vehicle
  // TODO add more special cases after testing
  if (o.contains('carjacking')) {
    out..add(CrimeCategory.violent)..add(CrimeCategory.vehicle);
  }

  if (out.isEmpty) out.add(CrimeCategory.other);
  return out;
}
