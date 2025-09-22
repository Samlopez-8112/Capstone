import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:capstone/screens/settings_screen.dart';
import 'package:capstone/screens/CrowdSource_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' hide LocationAccuracy;
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../consts.dart';
import '../models/poi_category.dart';
import '../services/places_service.dart';
import '../widgets/autocomplete_search_bar.dart';
import 'friend_screen.dart';
import '../models/crime_incident.dart';
//import '../services/crime_fixture_data_source.dart';
import '../models/crime_severity.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/location_permissions.dart';
import '../services/crimeometer_service.dart';
import '../utils/crimefilter.dart';
import 'dart:math' as math;
import '../offline_maps/offline_maps_page.dart';


class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _mapController = Completer();
  final Location _location = Location();

  LatLng? _currentPosition; // user’s current location
  bool isFollowingUser = true;
  bool _isDialOpen = false;

  // fields for crime filter
  // if filter is empty, will show all
  Set<CrimeCategory> _activeFilters = {};
  int _timeFilterDays = 0;
  static const int _maxTimeFilterDays = 30;

  // track if user is viewing crimes for filter button
  bool get _isCrimeViewActive => _lastCrimes.isNotEmpty;

  // Cache categories per incident to avoid recomputing every time
  final Map<String, Set<CrimeCategory>> _categoryCache = {};

  // save crimes currently rendered
  List<CrimeIncident> _lastRenderedCrimes = [];


  Future<void> _maybeOpenOfflineIfNoInternet() async {
  final initial = await Connectivity().checkConnectivity();
  if (mounted && initial == ConnectivityResult.none) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OfflineMapsPage()),
    );
    return;
  }

  Connectivity().onConnectivityChanged.listen((result) {
    if (!mounted) return;
    if (result == ConnectivityResult.none) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OfflineMapsPage()),
      );
    }
  });
}



  // Crime overlay
  // final FixtureCrimeDataSource _crimeSource = FixtureCrimeDataSource(path: 'assets/crime_example.json');  see crime data source service
  // 9/20/25 replaced _crimeSource with _crimeService for actual API call
  final CrimeometerService _crimeService = CrimeometerService();
  List<CrimeIncident> _lastCrimes = [];
  static const _crimePrefix = 'crime_'; // mark crime markers with a prefix for easier cleanup

  // Crime radius bar
  double _crimeRadius = 1609.34; // default to 1 mile, in meters
  LatLng? _crimeCenter; // center captured on hold

  // Map overlays
  final Map<PolylineId, Polyline> polylines = {};
  final Map<MarkerId, Marker> markers = {};
  MarkerId? _searchMarkerId;
  String _travelMode = "driving";
  bool _showModeButtons = false;
  List<Map<String, dynamic>> _steps = [];
  final FlutterTts flutterTts = FlutterTts();
  StreamSubscription<Position>? _positionStream;
  int _currentStepIndex = 0;
  bool _isSidebarOpen = false;

  // Nearby search state
  double _searchRadius = 2000;
  List<Map<String, dynamic>> _lastFetchedPOIs = [];

  static LatLng? _origin;
  static LatLng? _destination;

  // Heatmap state 
  final Set<Circle> _heatCircles = {};
  bool _showHeatmap = true;
  Timer? _boundsDebounce;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ratingsSub;

  // maps each circleId to rating doc fields for the details bottom sheet
  final Map<CircleId, Map<String, dynamic>> _circleMeta = {};

  @override
  void initState() {
    super.initState();
      _maybeOpenOfflineIfNoInternet(); // check connectivity and open offline map if none
      _checkUserAuthentication();
      _initLocationDependentFeatures();
      getLocationUpdates().then((_) {
      getPolylinePoints().then(generatePolyline);
    });
    fixPinnedLocationData();

    // Listen for location updates
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 10, // meters before triggering update
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      setState(() {
        _origin = LatLng(position.latitude, position.longitude);
      });

      // Recalculate route with new origin
      if (_destination != null) {
        _createRoute();
      }
    });
  }

  @override
  void dispose() {
    _boundsDebounce?.cancel();
    _ratingsSub?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  void _checkUserAuthentication() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to continue.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
      return Scaffold(
    body: _currentPosition == null
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  "Location access is required to display the map.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.location_on),
                  label: const Text("Grant Location Access"),
                  onPressed: () async {
                    final granted = await requestLocationPermission(context);
                    if (granted) {
                      await _initLocationDependentFeatures();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Location permission denied.")),
                      );
                    }
                  },
                ),
              ],
            ),
          )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition!,
                    zoom: 13,
                  ),
                  myLocationEnabled: true,
                  markers: Set<Marker>.of(markers.values),
                  polylines: Set<Polyline>.of(polylines.values),
                  circles: _showHeatmap ? _heatCircles : {},
                  onMapCreated: (controller) {
                    _mapController.complete(controller);
                    _scheduleBoundsRefresh();
                  },
                  onCameraMove: (_) => _scheduleBoundsRefresh(),
                  onCameraIdle: _refreshHeatForViewport,
                  onLongPress: _onMapLongPress,
                  onTap: _onMapTap,
                ),

                // Filter icon
                if (_isCrimeViewActive)
                Positioned(
                  top: 168, right: 16,
                  child: Material(
                    color: Colors.white,
                    elevation: 2,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.filter_alt_outlined),
                      tooltip: 'Filter crimes',
                      onPressed: _showCrimeFilterSheet,
                    ),
                  ),
                ),

                // Filter icon
                if (_isCrimeViewActive)
                Positioned(
                  top: 168, right: 16,
                  child: Material(
                    color: Colors.white,
                    elevation: 2,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.filter_alt_outlined),
                      tooltip: 'Filter crimes',
                      onPressed: _showCrimeFilterSheet,
                    ),
                  ),
                ),

                // Filter icon
                if (_isCrimeViewActive)
                Positioned(
                  top: 168, right: 16,
                  child: Material(
                    color: Colors.white,
                    elevation: 2,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.filter_alt_outlined),
                      tooltip: 'Filter crimes',
                      onPressed: _showCrimeFilterSheet,
                    ),
                  ),
                ),

                // Filter icon
                if (_isCrimeViewActive)
                Positioned(
                  top: 168, right: 16,
                  child: Material(
                    color: Colors.white,
                    elevation: 2,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.filter_alt_outlined),
                      tooltip: 'Filter crimes',
                      onPressed: _showCrimeFilterSheet,
                    ),
                  ),
                ),

                // search bar
                Positioned(
                  top: 15,
                  left: 5,
                  right: 5,
                  child: AutocompleteSearchBar(
                    onSuggestionSelected: (LatLng coords) async {
                      final controller = await _mapController.future;
                      setState(() {
                        isFollowingUser = false;
                        _destination = coords;

                        // remove previous search marker if it exists
                        if (_searchMarkerId != null) {
                          markers.remove(_searchMarkerId);
                        }

                        final markerId = const MarkerId("search_temp");
                        _searchMarkerId = markerId;

                        markers[markerId] = Marker(
                          markerId: markerId,
                          position: coords,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueCyan),
                              onTap: () => _openDetailsForLatLng(coords),
                          infoWindow:
                              const InfoWindow(title: "Searched Location"),
                        );
                      });

                      controller.animateCamera(
                        CameraUpdate.newLatLngZoom(coords, 13),
                      );

                      if (_origin != null && _destination != null) {
                        _createRoute();
                      }
                      await _openDetailsForLatLng(coords);
                    },
                  ),
                ),

                // route mode buttons
                if (_showModeButtons) 
                  Positioned(
                    top: 80,
                    left: 15,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            setState(() {
                              _travelMode = "driving";
                            });
                            _createRoute();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _travelMode == "driving"
                                ? Colors.blue
                                : Colors.grey[300],
                            foregroundColor: _travelMode == "driving"
                                ? Colors.white
                                : Colors.black,
                          ),
                          child: const Text("Car"),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            setState(() {
                              _travelMode = "bicycling";
                            });
                            _createRoute();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _travelMode == "bicycling"
                                ? Colors.blue
                                : Colors.grey[300],
                            foregroundColor: _travelMode == "bicycling"
                                ? Colors.white
                                : Colors.black,
                          ),
                          child: const Text("Bike"),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            setState(() {
                              _travelMode = "walking";
                            });
                            _createRoute();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _travelMode == "walking"
                                ? Colors.blue
                                : Colors.grey[300],
                            foregroundColor: _travelMode == "walking"
                                ? Colors.white
                                : Colors.black,
                          ),
                          child: const Text("Walk"),
                        ),
                      ],
                    ),
                  ),

                // cancel route button
                if (_destination != null)
                  Positioned(
                    top: 135,
                    left: 15,
                    child: FloatingActionButton(
                      heroTag: "cancelRouteBtn",
                      backgroundColor: Colors.red,
                      onPressed: _cancelRoute,
                      child: const Icon(Icons.close),
                    ),
                  ),

                // Sidebar panel
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: 200,
                  bottom: 210,
                  left: _isSidebarOpen ? 0 : -250, // slides in/out
                  child: Container(
                    width: 225,
                    color: Colors.white,
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: Text(
                              "Turn-by-Turn Directions",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _steps.isEmpty
                                ? const Center(child: Text("No route loaded"))
                                : ListView.builder(
                                    itemCount: _steps.length,
                                    itemBuilder: (context, index) {
                                      final step = _steps[index];
                                      return ListTile(
                                        leading: Icon(
                                          Icons.directions,
                                          color: index == _currentStepIndex
                                              ? Colors.blue
                                              : Colors.grey,
                                        ),
                                        title: Text(
                                          _stripHtml(step['instruction']),
                                          style: TextStyle(
                                            fontWeight: index == _currentStepIndex
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: index == _currentStepIndex
                                                ? Colors.blue
                                                : Colors.black,
                                          ),
                                        ),
                                        subtitle: Text(
                                          "${step['distance']} • ${step['duration']}",
                                        ),
                                        onTap: () {
                                          _speakStep(step['instruction']);
                                          setState(() {
                                            _currentStepIndex = index;
                                          });
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Navigation list button
                if (_destination != null)
                  Positioned(
                    top: 135,
                    left: 80,
                    child: FloatingActionButton(
                      heroTag: "TBTNavBtn",
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      onPressed: () {
                        setState(() {
                          _isSidebarOpen = !_isSidebarOpen;
                        });
                      },
                      child: const Icon(Icons.turn_right),
                    ),
                      
                    ),

                // Sign-out button
                Positioned(
                  top: 80,
                  right: 10,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 4,
                    ),
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Icon(Icons.logout),
                  ),
                ),

                // Settings (gear)
                Positioned(
                  top: 120,
                  right: 5,
                  child: IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      );
                    },
                  ),
                ),

                // Search radius slider (shown when speed dial is open)
                if (_isDialOpen)
                  Positioned(
                    bottom: 160,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(blurRadius: 6, color: Colors.black26)
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text("Search Radius (m)",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Slider(
                            value: _searchRadius,
                            min: 100,
                            max: 5000,
                            divisions: 49,
                            label: '${_searchRadius.round()}m',
                            onChanged: (value) =>
                                setState(() => _searchRadius = value),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Speed dial: nearby search by category
                Positioned(
                  bottom: 75,
                  left: 20,
                  child: SpeedDial(
                    icon: Icons.place,
                    activeIcon: Icons.close,
                    backgroundColor: Colors.blueAccent,
                    spacing: 12,
                    onOpen: () => setState(() => _isDialOpen = true),
                    onClose: () => setState(() => _isDialOpen = false),
                    children: PoiCategory.values.map((cat) {
                      return SpeedDialChild(
                        child: Image.asset(cat.iconPath, height: 24),
                        label: cat.label,
                        onTap: () {
                          setState(() {
                            isFollowingUser = false;
                          });
                          _fetchCategoryPOIs(cat);
                        },
                      );
                    }).toList(),
                  ),
                ),

                // Toggle follow user + clear temp overlays
                Positioned(
                  bottom: 90,
                  right: 20,
                  child: FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        isFollowingUser = !isFollowingUser;

                        // Remove temporary search marker if it exists
                        if (isFollowingUser && _searchMarkerId != null) {
                          markers.remove(_searchMarkerId);
                          _searchMarkerId = null;
                        }

                        // Always remove POIs when returning to self
                        if (isFollowingUser) {
                          markers.removeWhere((key, marker) =>
                              key.value.startsWith('poi_'));
                              _clearCrimeMarkers(); // clear crime markers as well
                        }
                      });

                      if (isFollowingUser && _currentPosition != null) {
                        _cameraTo(_currentPosition!);
                      }
                    },
                    child: Icon(isFollowingUser
                        ? Icons.my_location
                        : Icons.location_disabled),
                  ),
                ),

                // Heatmap toggle
                Positioned(
                  bottom: 200,
                  right: 20,
                  child: FloatingActionButton(
                    heroTag: 'heatToggle',
                    mini: true,
                    onPressed: () {
                      setState(() => _showHeatmap = !_showHeatmap);
                      if (_showHeatmap) {
                        _scheduleBoundsRefresh();
                      } else {
                        _ratingsSub?.cancel();
                        setState(() => _heatCircles.clear());
                      }
                    },
                    child: Icon(
                        _showHeatmap ? Icons.visibility : Icons.visibility_off),
                  ),
                ),

                // Pinned locations
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton(
                    onPressed: _showPinnedLocations,
                    child: const Icon(Icons.bookmark),
                  ),
                ),

                // Friends
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FriendScreen()),
                      );
                    },
                    child: const Text("Friends"),
                  ),
                ),

                // Show location-sharing friends
                Positioned(
                  bottom: 140,
                  left: 20,
                  child: FloatingActionButton(
                    onPressed: _showSharingFriends,
                    child: const Icon(Icons.people),
                  ),
                ),

                // Community Rating (CrowdSource) screen button
                Positioned(
                  bottom: 150,
                  right: 20,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text("Rating"),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const RateAreaScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  //Heatmap helpers (viewport streaming, color/intensity, details)
  void _scheduleBoundsRefresh() {
    _boundsDebounce?.cancel();
    _boundsDebounce =
        Timer(const Duration(milliseconds: 250), _refreshHeatForViewport);
  }

  Future<void> _refreshHeatForViewport() async {
    if (!_showHeatmap) return;

    final controller = await _mapController.future;

    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }

    final north = max(bounds.northeast.latitude, bounds.southwest.latitude);
    final south = min(bounds.northeast.latitude, bounds.southwest.latitude);
    final east = max(bounds.northeast.longitude, bounds.southwest.longitude);
    final west = min(bounds.northeast.longitude, bounds.southwest.longitude);

    _ratingsSub?.cancel();
    _ratingsSub = FirebaseFirestore.instance
        .collectionGroup('ratings')
        .where('center.lat', isGreaterThanOrEqualTo: south)
        .where('center.lat', isLessThanOrEqualTo: north)
        .orderBy('center.lat')
        .limit(1500)
        .snapshots()
        .listen((snap) {
      final now = DateTime.now();
      final Set<Circle> circles = {};
      final Map<CircleId, Map<String, dynamic>> meta = {};

      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = (d['center']?['lat'] as num?)?.toDouble();
        final lng = (d['center']?['lng'] as num?)?.toDouble();
        final rating = (d['rating'] as num?)?.toDouble();
        final radiusMi = (d['radiusMiles'] as num?)?.toDouble() ?? 0.5;
        final ts = (d['timestamp'] as Timestamp?)?.toDate();

        if (lat == null || lng == null || rating == null) continue;

        // client-side longitude filter
        if (lng < west || lng > east) continue;

        // weight lower safety => higher intensity with time decay
        final base = (5.0 - rating).clamp(0.0, 4.0); // 5 = safer
        final ageDays = ts == null ? 0.0 : now.difference(ts).inHours / 24.0;
        const halfLifeDays = 60.0; // newer reports weigh more
        final decay = pow(0.5, ageDays / halfLifeDays).toDouble(); // 1..0
        final intensity = (base * decay) / 4.0; // normalize 0..1

        if (intensity <= 0.02) continue;

        // circle radius in meters (cap for perf/visuals)
        final kernel = (radiusMi * 1609.34 * 0.35).clamp(80.0, 450.0);
        final id = CircleId(
            '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}_${doc.id}');

        circles.add(
          Circle(
            circleId: id,
            center: LatLng(lat, lng),
            radius: kernel,
            strokeWidth: 0,
            fillColor: _colorForIntensity(intensity),
          ),
        );

        meta[id] = {
          'rating': rating,
          'reasons': d['reasons'],
          'personalExperienceDetail': d['personalExperienceDetail'],
          'timestamp': ts,
          'radiusMiles': radiusMi,
          'center': {'lat': lat, 'lng': lng},
        };
      }

      setState(() {
        _heatCircles
          ..clear()
          ..addAll(circles);
        _circleMeta
          ..clear()
          ..addAll(meta);
      });
    }, onError: (e) {
      debugPrint('Heatmap stream error: $e');
    });
  }

  Color _colorForIntensity(double t) {
    t = t.clamp(0.0, 1.0);
    Color lerp(Color a, Color b, double x) =>
        Color.lerp(a, b, x.clamp(0, 1))!;

    // gradient green -> yellow -> red
    final Color col = t < 0.5
        ? lerp(Colors.green.shade400, Colors.yellow.shade600, t / 0.5)
        : lerp(Colors.yellow.shade600, Colors.red.shade800, (t - 0.5) / 0.5);

    final alpha = (40 + (t * 120)).round(); // 40..160 alpha
    return col.withAlpha(alpha);
  }

  void _onMapTap(LatLng pos) {
    if (!_showHeatmap || _heatCircles.isEmpty) return;

    // find circles that contain the tap (distance is radius)
    final matches = _heatCircles.where((c) {
      final d =
          _calculateDistanceMeters(pos, c.center.latitude, c.center.longitude);
      return d <= c.radius;
    }).toList();

    if (matches.isEmpty) return;

    // prefer the closest center to the tap
    matches.sort((a, b) {
      final da = _calculateDistanceMeters(
          pos, a.center.latitude, a.center.longitude);
      final db = _calculateDistanceMeters(
          pos, b.center.latitude, b.center.longitude);
      return da.compareTo(db);
    });

    final CircleId id = matches.first.circleId;
    final data = _circleMeta[id];
    if (data != null) _showRatingDetailsSheet(data);
  }

  void _showRatingDetailsSheet(Map<String, dynamic> d) {
    final List reasons = (d['reasons'] as List?) ?? const [];
    final String? detail = (d['personalExperienceDetail'] as String?)?.trim();
    final double? rating = (d['rating'] as num?)?.toDouble();
    final double? radiusMi = (d['radiusMiles'] as num?)?.toDouble();
    final DateTime? ts = d['timestamp'] is Timestamp
        ? (d['timestamp'] as Timestamp).toDate()
        : d['timestamp'] as DateTime?;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.shield_outlined),
                const SizedBox(width: 8),
                Text('Community rating',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (rating != null)
                  Row(children: [
                    const Icon(Icons.star, size: 18, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1)),
                  ]),
              ]),
              const SizedBox(height: 8),
              if (radiusMi != null)
                Text('Reported radius: ${radiusMi.toStringAsFixed(2)} mi',
                    style: Theme.of(context).textTheme.bodySmall),
              if (ts != null)
                Text('Updated: ${ts.toLocal()}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600])),

              const SizedBox(height: 12),
              Text('Reasons', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              if (reasons.isEmpty)
                const Text('No reasons provided')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons
                      .map<Widget>((r) => Chip(label: Text(r.toString())))
                      .toList(),
                ),

              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Personal experience',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(detail),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _initLocationDependentFeatures() async {
  final granted = await requestLocationPermission(context);
  debugPrint("Location permission granted: $granted");
  if (!granted) return;

  await getLocationUpdates();
  final points = await getPolylinePoints();
  generatePolyline(points);
}


  // Location / camera / polyline

  Future<void> getLocationUpdates() async {
    if (!await _location.serviceEnabled()) await _location.requestService();
    if (await _location.hasPermission() == PermissionStatus.denied) {
      await _location.requestPermission();
    }

    _location.onLocationChanged.listen((loc) {
      debugPrint("Got location update: ${loc.latitude}, ${loc.longitude}");
      if (loc.latitude != null && loc.longitude != null) {
        final pos = LatLng(loc.latitude!, loc.longitude!);
        setState(() => _currentPosition = pos);
        if (isFollowingUser) _cameraTo(pos);
      }
    });
  }

  Future<void> _cameraTo(LatLng pos) async {
    final controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(pos, 13));
  }

  Future<List<LatLng>> getPolylinePoints() async {
    if (_currentPosition == null) {
      LocationData locationData = await _location.getLocation();
      _currentPosition = LatLng(locationData.latitude!, locationData.longitude!);
    }

    _origin = _currentPosition;

    if (_destination == null) {
      return [];
    }
    
    final result = await PolylinePoints().getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(_origin!.latitude, _origin!.longitude),
        destination: PointLatLng(_destination!.latitude, _destination!.longitude),
        mode
          : _travelMode == "driving"? TravelMode.driving
          : _travelMode == "bicycling"? TravelMode.bicycling
          : TravelMode.walking //else
      ),
      googleApiKey: GOOGLE_MAPS_API_KEY,
    );
    _showModeButtons = true;
    return result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  void generatePolyline(List<LatLng> coordinates) {
    final id = const PolylineId("poly");
    polylines[id] = Polyline(
      polylineId: id,
      color: Colors.blue,
      width: 6,
      points: coordinates,
    );
    setState(() {});
  }  

  void _cancelRoute() {
    setState(() {
      _isSidebarOpen = false;
      _showModeButtons = false;
      _destination = null;
      _steps = [];
      polylines.clear();
      if (_searchMarkerId != null) {
        markers.remove(_searchMarkerId);
        _searchMarkerId = null;
      }
    });
  }

// fetch route + step instructions
Future<List<Map<String, dynamic>>> _getDirectionsWithSteps(
  double originLat,
  double originLng,
  double destLat,
  double destLng,
  String mode,
) async {
  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/directions/json'
    '?origin=$originLat,$originLng'
    '&destination=$destLat,$destLng'
    '&mode=$mode'
    '&key=$GOOGLE_MAPS_API_KEY',
  );

  final response = await http.get(url);

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);

    final steps = data['routes'][0]['legs'][0]['steps'] as List;

    return steps.map((s) => {
      'instruction': s['html_instructions'],
      'distance': s['distance']['text'],
      'duration': s['duration']['text'],
      'start': s['start_location'],
      'end': s['end_location'],
    }).toList();
  } else {
    throw Exception('Failed to load directions');
  }
}

Future<void> _createRoute() async {
  //generate route
  final points = await getPolylinePoints();
  generatePolyline(points);

  // fetch step-by-step directions
  final steps = await _getDirectionsWithSteps(
    _origin!.latitude,
    _origin!.longitude,
    _destination!.latitude,
    _destination!.longitude,
    _travelMode,
  );

  setState(() {
    _showModeButtons = true;
    _steps = steps;
  });
}

// text-to-speech
Future<void> _speakStep(String text) async {
  await flutterTts.speak(_stripHtml(text));
}

  // helper to remove <b> tags etc. from Google instructions
  String _stripHtml(String htmlText) {
    return htmlText.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  // POIs / Places 

  // Handle marker tap and fetch place details (full info: name, address, phone, website, rating)
  Future<void> _handleMarkerTap(String placeId) async {
    try {
      final placeDetails = await PlaceApiProvider().fetchPlaceDetails(placeId);
      _showPlaceDetailsBottomSheet(placeDetails);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching place details: $e')),
      );
    }
  }

  void _showPlaceDetailsBottomSheet(Map<String, dynamic> placeDetails) {
    final lat = (placeDetails['geometry']?['location']?['lat'] as num?)?.toDouble();
    final lng = (placeDetails['geometry']?['location']?['lng'] as num?)?.toDouble();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              placeDetails['name'] ?? 'No name',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text('Address: ${placeDetails['formatted_address'] ?? 'No address'}'),
            const SizedBox(height: 10),
            Text('Phone: ${placeDetails['formatted_phone_number'] ?? 'No phone number'}'),
            const SizedBox(height: 10),
            Text('Website: ${placeDetails['website'] ?? 'No website'}'),
            const SizedBox(height: 10),
            Text('Rating: ${placeDetails['rating'] ?? 'No rating'}'),
            const SizedBox(height: 10),
            if (lat != null && lng != null)
              ElevatedButton(
                onPressed: () => _launchNavigation(lat, lng),
                child: const Text('Navigate to this place'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchCategoryPOIs(PoiCategory category) async {
    if (_currentPosition == null) return;
    try {
      final results = await NearbyPlacesService().fetchNearby(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        category: category,
        radius: _searchRadius.round(),
      );

      // NEW: cache results for offline mode
      await _cachePOIs(category, results);

      setState(() {
        _lastFetchedPOIs = results;
        markers.removeWhere(
            (key, marker) => key.value.startsWith('poi_'));

        for (final poi in results) {
          final lat = (poi['geometry']?['location']?['lat'] as num?)?.toDouble();
          final lng = (poi['geometry']?['location']?['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;

          final placeId = poi['place_id'] as String?;
          final markerId = MarkerId('poi_${placeId ?? '${lat}_${lng}'}');

          markers[markerId] = Marker(
            markerId: markerId,
            position: LatLng(lat, lng),
            // Only wire to place details if we have a real place_id
            onTap: placeId == null ? null : () => _handleMarkerTap(placeId),
            infoWindow: InfoWindow(
              title: poi['name']?.toString() ?? 'POI',
              snippet: poi['vicinity']?.toString() ?? '',
              onTap: () => _launchNavigation(lat, lng),
            ),
          );
        }
      });

      _showPOIListSheet();
    } catch (e) {
      debugPrint('Error fetching ${category.label}: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch ${category.label} nearby')),
      );
    }
  }

  // Save POIs to disk for offline use (same folder structure OfflineMapsPage reads)
  Future<void> _cachePOIs(
    PoiCategory category,
    List<Map<String, dynamic>> pois,
  ) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final offlineDir = Directory('${dir.path}/offline/pois');
      await offlineDir.create(recursive: true);

      // keep a file per category near current location for simplicity
      final file = File('${offlineDir.path}/pois_${category.name}.json');
      await file.writeAsString(json.encode({'pois': pois}));

      debugPrint('Cached ${pois.length} ${category.label} POIs -> ${file.path}');
    } catch (e) {
      debugPrint('Failed to cache POIs: $e');
    }
  }

  void _showPOIListSheet() {
    final sorted = [..._lastFetchedPOIs]
      ..sort((a, b) {
        final aLat = (a['geometry']?['location']?['lat'] as num?)?.toDouble() ?? 0;
        final aLng = (a['geometry']?['location']?['lng'] as num?)?.toDouble() ?? 0;
        final bLat = (b['geometry']?['location']?['lat'] as num?)?.toDouble() ?? 0;
        final bLng = (b['geometry']?['location']?['lng'] as num?)?.toDouble() ?? 0;
        return _calculateDistanceMeters(_currentPosition!, aLat, aLng)
            .compareTo(_calculateDistanceMeters(_currentPosition!, bLat, bLng));
      });

    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final poi = sorted[i];
          final lat = (poi['geometry']?['location']?['lat'] as num?)?.toDouble();
          final lng = (poi['geometry']?['location']?['lng'] as num?)?.toDouble();
          final name = poi['name']?.toString() ?? 'Unknown';
          final vicinity = poi['vicinity']?.toString() ?? 'No address';

          return ListTile(
            leading: const Icon(Icons.location_on),
            title: Text(name),
            subtitle: (lat != null && lng != null)
                ? Text('$vicinity • ${_calculateDistanceMeters(_currentPosition!, lat, lng).round()}m')
                : Text(vicinity),
            trailing: (lat != null && lng != null)
                ? IconButton(
                    icon: const Icon(Icons.navigation),
                    onPressed: () => _launchNavigation(lat, lng),
                  )
                : null,
            onTap: () async {
              if (lat == null || lng == null) return;
              final controller = await _mapController.future;
              controller.animateCamera(
                CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
              );
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  // Pinned / friends

  Future<void> _handleLongPressPin(LatLng pos) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('pinned_locations')
          .add({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'isFavorite': false,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pinned location saved!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving pinned location: $e')),
      );
    }
  }

  Future<void> _showPinnedLocations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('pinned_locations')
        .orderBy('timestamp', descending: true)
        .get();

    final favs = snapshot.docs.where((doc) {
      final data = doc.data();
      return data.containsKey('isFavorite') && data['isFavorite'] == true;
    });

    final recents = snapshot.docs.where((doc) {
      final data = doc.data();
      return !data.containsKey('isFavorite') || data['isFavorite'] != true;
    }).take(3);

    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: [
          const ListTile(title: Text('Favorites')),
          ...favs.map((doc) => _buildPinTile(doc, user.uid)),
          const Divider(),
          const ListTile(title: Text('Recent Pins')),
          ...recents.map((doc) => _buildPinTile(doc, user.uid)),
        ],
      ),
    );
  }

  Widget _buildPinTile(QueryDocumentSnapshot doc, String uid) {
    final lat = doc['lat'];
    final lng = doc['lng'];
    final isFav = doc['isFavorite'] == true;

    return ListTile(
      leading: Icon(isFav ? Icons.star : Icons.star_border),
      title: Text('Lat: $lat, Lng: $lng'),
      trailing: IconButton(
        icon: Icon(isFav ? Icons.star : Icons.star_border),
        onPressed: () {
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('pinned_locations')
              .doc(doc.id)
              .update({'isFavorite': !isFav});
          Navigator.pop(context);
          _showPinnedLocations();
        },
      ),
      onTap: () {
        Navigator.pop(context);
        _cameraTo(LatLng(lat, lng));
      },
    );
  }

  Future<void> fixPinnedLocationData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('pinned_locations')
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!data.containsKey('isFavorite')) {
        await doc.reference.update({'isFavorite': false});
      }
    }
  }

  Future<void> _showSharingFriends() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // find all users who are sharing with current user
    final allUsers = await FirebaseFirestore.instance.collection('users').get();
    final sharedWithMe = <DocumentSnapshot>[];

    for (final doc in allUsers.docs) {
      if (doc.id == user.uid) continue;
      final sharedDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(doc.id)
          .collection('shared_locations')
          .doc(user.uid)
          .get();
      if (sharedDoc.exists && sharedDoc['isSharing'] == true) {
        sharedWithMe.add(doc);
      }
    }

    if (sharedWithMe.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No friends are sharing with you.")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: sharedWithMe.map((doc) {
          final displayName = doc['displayName'] ?? doc.id;
          return ListTile(
            leading: const Icon(Icons.person_pin_circle),
            title: Text(displayName),
            onTap: () async {
              Navigator.pop(context);
              final loc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(doc.id)
                  .collection('location')
                  .doc('current')
                  .get();

              if (!loc.exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$displayName has no location data.")),
                );
                return;
              }

              final lat = (loc['lat'] as num).toDouble();
              final lng = (loc['lng'] as num).toDouble();
              final pos = LatLng(lat, lng);
              _cameraTo(pos);

              final id = MarkerId("friend_${doc.id}");
              setState(() {
                markers[id] = Marker(
                  markerId: id,
                  position: pos,
                  infoWindow: InfoWindow(title: displayName),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueMagenta),
                );
              });

              Future.delayed(const Duration(seconds: 5), () {
                setState(() => markers.remove(id));
              });
            },
          );
        }).toList(),
      ),
    );
  }

  // Remove all markers whose MarkerId.value have "crime_" prefix
  void _clearCrimeMarkers() {
    markers.removeWhere((id, _) => id.value.startsWith(_crimePrefix));
    setState(() {});
  }

  // Info provided on click of a crime pin (YYYY-MM-DD HH:MM:SS.sss - Location)
  String _crimeSnippet(CrimeIncident c) {
    final when = c.occurredAt.toLocal().toString();
    final where = c.address ?? '${c.position.latitude.toStringAsFixed(4)}, ${c.position.longitude.toStringAsFixed(4)}';
    return '$when - $where';
  }

  // Show bottom modal listing returned crimes
  bool _isCrimesSheetOpen = false;

  void _showCrimesListSheet() {
    if (_lastCrimes.isEmpty || _isCrimesSheetOpen) return; // return if theres no crimes
    _isCrimesSheetOpen = true; // track if crime sheet is open
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: _lastCrimes.length,
        itemBuilder: (_, i) {
          final c = _lastCrimes[i];
          // for each crime, calculate distance
          final dist = _calculateDistanceMeters(_currentPosition!, c.position.latitude, c.position.longitude).round();
          // each crime returns a ListTile with basic icon, 
          //the offense in question, address, and distance
          return ListTile(
            leading: const Icon(Icons.report),
            title: Text(c.offense),
            subtitle: Text('${c.occurredAt.toLocal()} - ${c.address ?? 'Unknown address'} - ${dist}m'),
            // code reused from POI logic, allow the user to navigate to a incident scene
            trailing: IconButton(
              icon: const Icon(Icons.navigation),
              onPressed: () => _launchNavigation(c.position.latitude, c.position.longitude),
            ),
            // on tap of a list object, move the camera to it's coordinates, close modal
            onTap: () async {
              final controller = await _mapController.future;
              controller.animateCamera(CameraUpdate.newLatLngZoom(c.position, 15));
              Navigator.pop(context);
            },
          );
        },
      ),
    );
    _isCrimesSheetOpen = false;
  }

  // Long press handler 
  void _onMapLongPress(LatLng pos) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            // On click of 'save location', call _savePinnedLocation for the area
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Save location'),
              onTap: () {
                Navigator.pop(context); // close menu
                _handleLongPressPin(pos);
              },
            ),
            // On click of 'view crimes' call Crime radius selector function
            // crime viewer handled in _showCrimeRadiusSheet
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('View recent crimes here'),
              onTap: () async {
                Navigator.pop(context); // close menu
                setState(() => isFollowingUser = false);
                await _cameraTo(pos);

                // set the center coord to held position
                _crimeCenter = pos;
                setState(() {});
                // show the draggable radius sheet
                _showCrimeRadiusSheet();
              },),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    }

  // Open a drag bar for radius
  // Repurposes code from POI radius slider
  void _showCrimeRadiusSheet() {
    // Bottom sheet
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        // Local setState for the sheet’s own UI
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              // box to hold slider bar for radius
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sheet title and current radius value displayed here
                  Row(
                    children: [
                      const Text('Crime radius (m)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${_crimeRadius.round()} m'),
                    ],
                  ),
                  // Radius slider
                  Slider(
                    value: _crimeRadius,
                    min: 100,
                    max: 5000,
                    divisions: 49,
                    onChanged: (v) {
                    setLocal(() => _crimeRadius = v);}, // update label live
                    onChangeEnd: (v) async {
                      Navigator.pop(ctx); // close the radius bar once it's been selected
                      if (_crimeCenter != null) {
                        await _loadCrimesAt(
                          center: _crimeCenter!,
                          radiusMeters: v,
                          daysAgo: 30, // shows crimes within 30 day period
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8), 
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon( // close button
                      icon: const Icon(Icons.close),
                      label: const Text('Close'), 
                      onPressed: () => Navigator.pop(ctx), // close the modal on click of 'close'
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() { //runs on close of the radius bar, cleans up.
    });
  }
  

    // calculate distance using Haversine formula 
    double _calculateDistanceMeters(
        LatLng from, double lat2, double lng2) {
      const R = 6371000;
      final dLat = (lat2 - from.latitude) * (pi / 180);
      final dLng = (lng2 - from.longitude) * (pi / 180);
      final a = 0.5 -
          cos(dLat) / 2 +
          cos(from.latitude * pi / 180) *
              cos(lat2 * pi / 180) *
              (1 - cos(dLng)) / 2;
      return R * 2 * asin(sqrt(a));
    }

    // open Google Maps with selected coordinates
    Future<void> _launchNavigation(double lat, double lng) async {
      final uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch Google Maps.')),
          );
        }
      }
    }
    //
  Future<void> _openDetailsForLatLng(LatLng pos) async {
    try {
      final details = await PlaceApiProvider().fetchNearestEstablishmentDetails(pos);
      if (!mounted) return;
      _showPlaceCrimeSheet(center: pos, details: details);

      if (details != null) {
        // Reuse your existing POI bottom sheet (already renders
        // address, phone, website, rating, and a Navigate button).
      } else {
        // Nothing business-like nearby; show a simple fallback.
        _showBasicLocationSheet(pos);
      }
    } catch (e) {
      if (!mounted) return;
      _showBasicLocationSheet(pos);
    }
  }

  // Fallback sheet for raw coordinates (no business found).
  void _showBasicLocationSheet(LatLng pos) {
    final from = _currentPosition ?? pos;
    final distM = _calculateDistanceMeters(from, pos.latitude, pos.longitude).round();
    final label = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.place),
              const SizedBox(width: 8),
              Text('Selected location', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text('~${distM}m away', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save'),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _handleLongPressPin(pos);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('View crimes'),
                  onPressed: () async {
                    Navigator.pop(context);
                    setState(() => isFollowingUser = false);
                    _crimeCenter = pos;
                    await _cameraTo(pos);
                    _showCrimeRadiusSheet();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.navigation),
                  label: const Text('Navigate'),
                  onPressed: () {
                    Navigator.pop(context);
                    _launchNavigation(pos.latitude, pos.longitude);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaceCrimeSheet({
    required LatLng center,
    required Map<String, dynamic>? details,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,      // allows a taller sheet
      showDragHandle: true,
      builder: (_) {
        final height = MediaQuery.of(context).size.height * 0.55;
        return DefaultTabController(
          length: 2,
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Place'),
                    Tab(text: 'Crime'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildPlaceDetailsView(center, details),
                      _buildCrimeSummaryView(center),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildPlaceDetailsView(LatLng fallbackPos, Map<String, dynamic>? d) {
    final name    = d?['name'] as String? ?? 'Selected location';
    final address = d?['formatted_address'] as String?
        ?? '${fallbackPos.latitude.toStringAsFixed(5)}, ${fallbackPos.longitude.toStringAsFixed(5)}';
    final phone   = d?['formatted_phone_number'] as String?;
    final website = d?['website'] as String?;
    final rating  = (d?['rating'] is num) ? (d!['rating'] as num).toDouble() : null;

    final lat = (d?['geometry']?['location']?['lat'] as num?)?.toDouble() ?? fallbackPos.latitude;
    final lng = (d?['geometry']?['location']?['lng'] as num?)?.toDouble() ?? fallbackPos.longitude;
    final pos = LatLng(lat, lng);

    final from = _currentPosition ?? pos;
    final distM = _calculateDistanceMeters(from, pos.latitude, pos.longitude).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ListView(
        children: [
          Row(
            children: [
              const Icon(Icons.place),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
              if (rating != null) ...[
                const Icon(Icons.star, size: 18, color: Colors.amber),
                const SizedBox(width: 4),
                Text(rating.toStringAsFixed(1)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(address, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            'LatLng: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} • ${distM}m away',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
          ),
          if (phone != null || website != null) ...[
            const SizedBox(height: 12),
            if (phone != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone),
                title: Text(phone),
                onTap: () => launchUrl(Uri.parse('tel:$phone')),
              ),
            if (website != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.public),
                title: Text(website, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => launchUrl(Uri.parse(website), mode: LaunchMode.externalApplication),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save'),
                onPressed: () async {
                  Navigator.pop(context);
                  await _handleLongPressPin(pos);
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.shield_outlined),
                label: const Text('View crimes'),
                onPressed: () async {
                  Navigator.pop(context);
                  setState(() => isFollowingUser = false);
                  _crimeCenter = pos;
                  await _cameraTo(pos);
                  _showCrimeRadiusSheet();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildCrimeSummaryView(LatLng center) {
    final radius = _crimeRadius; // use current slider default/value
    const days = 30;

  return FutureBuilder<List<CrimeIncident>>(
    //future: _crimeSource.fetchIncidents(
    future: _fetchCrimeometerIncidents(
      center: center,
      radiusMeters: radius,
      daysAgo: days,
    ),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snap.hasError) {
        return Center(child: Text('Could not load crime data.'));
      }
      final crimes = snap.data ?? const <CrimeIncident>[];
      if (crimes.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No incidents found',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Within ${(radius / 1609.34).toStringAsFixed(2)} mi • last $days days',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Change radius'),
                  onPressed: () {
                    Navigator.pop(context);
                    _crimeCenter = center;
                    _showCrimeRadiusSheet();
                  },
                ),
              ),
            ],
          ),
        );
      }

        // Count by offense
        final Map<String, int> byType = {};
        for (final c in crimes) {
          final key = (c.offense.isNotEmpty ? c.offense : 'Unknown').trim();
          byType[key] = (byType[key] ?? 0) + 1;
        }
        final entries = byType.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)); // desc by count

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${crimes.length} incidents',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Within ${(radius / 1609.34).toStringAsFixed(2)} mi • last $days days',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),

              // Breakdown list
              Expanded(
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.report),
                      title: Text(e.key),
                      trailing: Text(e.value.toString()),
                    );
                  },
                ),
              ),

            // Actions
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Change radius'),
                  onPressed: () {
                    Navigator.pop(context);
                    _crimeCenter = center;
                    _showCrimeRadiusSheet();
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.list),
                  label: const Text('View list'),
                  onPressed: () {
                    // Reuse your existing list sheet
                    _lastCrimes = crimes;
                    Navigator.pop(context);
                    _showCrimesListSheet();
                  },
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
  // Fetch incidents from Crimeometer, place markers and display popup
  _loadCrimesAt({
    required LatLng center,
    required double radiusMeters,
    required int daysAgo,
    }) async {
    try {
      // Fetch data from Crimeometer
      final incidents = await _fetchCrimeometerIncidents(
        center: center,
        radiusMeters: radiusMeters,
        daysAgo: daysAgo,
      );

      // Clear old crime markers on new search
      markers.removeWhere((id, _) => id.value.startsWith(_crimePrefix));

      // For every incident, create a crime marker, give each a unique ID
      _lastCrimes = incidents;
      _categoryCache.clear();
      _renderFilteredCrimes();
      // _showCrimesListSheet();

    setState(() {});       // refreshes map
    _showCrimesListSheet(); // display the crimes on bottom popup 
  } catch (e) {
    debugPrint('Crime load error: $e'); // error handling
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load crime data for this area.')),
      );
    }
  }
}
 
// Assisted by ChatGPT, up-to-date method for retrieving data from crimeometer.
Future<List<CrimeIncident>> _fetchCrimeometerIncidents({
  required LatLng center,
  required double radiusMeters,
  required int daysAgo,
  int page = 1,
  int? pageSize,
}) async {
  // Call crimeometer_service
  final payload = await _crimeService.fetchCrimeData(
    latitude: center.latitude,
    longitude: center.longitude,
    distanceMiles: radiusMeters / 1609.34, // 1 mile, in meters
    daysAgo: daysAgo,
    page: page,
    pageSize: pageSize,
  );

  // Convert incidents to a list of objects
  final raw = _extractIncidentObjects(payload);

  // map output to incident model
  final out = <CrimeIncident>[];
  for (final it in raw) {
  if (it is! Map<String, dynamic>) continue;

  // parse latitude and longitude (used in marker ids)
  final lat = _pickDouble(it, ['incident_latitude', 'latitude', 'lat']);
  final lon = _pickDouble(it, ['incident_longitude', 'longitude', 'lon', 'lng']);
  if (lat == null || lon == null) continue;

  // grab offense type
  final offense = _pickString(it, [
    'incident_offense', 'offense', 'incident_type', 'ucr_offense', 'nibrs_code'
  ]) ?? 'Unknown';

  // grab time
  final whenStr = _pickString(it, [
    'incident_date', 'incident_datetime', 'reported_at', 'date', 'datetime'
  ]);
  DateTime occurredAt;
  try {
    occurredAt = whenStr != null ? DateTime.parse(whenStr).toUtc() : DateTime.now().toUtc();
  } catch (_) {
    occurredAt = DateTime.now().toUtc();
  }

  // grab address
  final addr = _pickString(it, ['incident_address', 'address', 'formatted_address', 'block_address']);

  // look for an incident ID for display purposes
  final id =
      _pickString(it, ['incident_id', 'incident_reference', 'incident_uid', 'case_number', 'incident_number', 'id'])
      ?? '${lat.toStringAsFixed(6)}_${lon.toStringAsFixed(6)}_${occurredAt.millisecondsSinceEpoch}';

    // outputs an object of 'CrimeIncident' type
    out.add(CrimeIncident(
      id: id,
      offense: offense,
      occurredAt: occurredAt,
      position: LatLng(lat, lon),
      address: addr,
      source: 'crimeometer',
    ));
  }
    return out;
  }

  /// Grabs incident objects as a list, tries various labels that might denote a new incident
  List<dynamic> _extractIncidentObjects(Map<String, dynamic> payload) {
    final i1 = payload['incidents'];
    if (i1 is List) return i1;

    final i2 = payload['data'];
    if (i2 is List) return i2;

    if (payload['results'] is List) return (payload['results'] as List);

    if (i2 is Map && i2['incidents'] is List) return (i2['incidents'] as List);

    // Error handling: empty list if nothings recognized
    return const [];
  }

  // pickString helper, chatGPT
  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  // pickDouble helper, chatGPT
  double? _pickDouble(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      final d = double.tryParse(s);
      if (d != null) return d;
    }
    return null;
  }

  // Return category of an incident based on offense title
  // Offense categories are laid out in utils/crimefilter.dart
  Set<CrimeCategory> _catsFor(CrimeIncident c) {
    return _categoryCache.putIfAbsent(c.id, () => categoriesForOffense(c.offense));
  }

  // Returns a list of incidents that match filter
  // If no filter is applied, returns the list as it was
List<CrimeIncident> _applyFilters(List<CrimeIncident> all) {
  var cur = all;

  // time filter
  // return crimes that have occured after (now - timeframe)
  if (_timeFilterDays > 0) {
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: _timeFilterDays));
    cur = cur.where((c) => c.occurredAt.isAfter(cutoff)).toList();
  }

  // category filter
  // if any category selected matches, add to list
  // this allows for selection of multiple categories
  if (_activeFilters.isNotEmpty) {
    cur = cur.where((c) {
      final cats = _catsFor(c);
      return cats.any(_activeFilters.contains);
    }).toList();
  }

  return cur;
}

  /// Display map markers as defined by the filter
  /// If the filter is empty, all are displayed (see _applyFilters)
  void _renderFilteredCrimes() {

    final filtered = _applyFilters(_lastCrimes); // filtered crime list

    // Remove old crime markers
    markers.removeWhere((id, _) => id.value.startsWith(_crimePrefix));
    _coordHitCounts.clear(); // for jitter assistant ; prevents crimes from stacking atop eachother

    // Display the markers
    for (final c in filtered) {
      final sev = classifySeverity(c.offense);
      final mId = MarkerId('$_crimePrefix${c.id}');
      final pos = _jitterIfDuplicate(c.position); // jitter helper call, overlapping incidents move a few units

      // place marker at position 
      markers[mId] = Marker(
        markerId: mId,
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(sev.hue),
        infoWindow: InfoWindow(
          title: '${c.offense} (${sev.label})', //offense title and severity on click
          snippet: _crimeSnippet(c), 
        ),
      );
    }

    _lastRenderedCrimes = filtered; // track most recently rendered crimes
    setState(() {}); // triggers visual for markers
  }

  // Crime popup bottom sheet, displays "FilterChips" for selection of crimes
  // displays categories, enumerates crimes per category
  // calls _renderFilteredCrimes on click of a button
  Future<void> _showCrimeFilterSheet() async {
    // Snapshot current selection
    final local = Set<CrimeCategory>.from(_activeFilters);
    int localDays = _timeFilterDays; //grab date from slider bar for filter

    // Helper to display amount of crimes with time selection
    Map<CrimeCategory, int> computeCounts() {
      // Apply time filter only, before category filter
      final base = () {
        if (localDays <= 0) return _lastCrimes;
        final cutoff = DateTime.now().toUtc().subtract(Duration(days: localDays));
        return _lastCrimes.where((c) => c.occurredAt.isAfter(cutoff)).toList();
      }();

      //count crimes per category from crimes within timeframe
      final map = <CrimeCategory, int>{};
      for (final c in base) {
        for (final cat in _catsFor(c)) {
          map[cat] = (map[cat] ?? 0) + 1;
        }
      }
      return map;
    }

    Map<CrimeCategory, int> counts = computeCounts();

    // label on button, category name + amount in area
    String label(CrimeCategory cat, String text) {
      final n = counts[cat] ?? 0;
      return n > 0 ? '$text ($n)' : text;
    }

    // Filter selection popup sheet
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          Widget chip(CrimeCategory cat, String text) {
            final sel = local.contains(cat);
            // options are instances of FilterChips 
            return FilterChip(
              label: Text(label(cat, text)),
              selected: sel,
              onSelected: (_) {
                setLocal(() {
                  // move on to next chip data before displaying
                  sel ? local.remove(cat) : local.add(cat);
                });
              },
            );
          }

          // Label for date and time slider
          String daysLabel(int d) => d == 0 ? 'All time' : 'Last $d day${d == 1 ? "" : "s"}';

          // Visual for filter popup
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter crimes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),

                // Slider for days since filter
                Text('Timeframe: ${daysLabel(localDays)}', style: const TextStyle(fontWeight: FontWeight.w500)),
                Slider(
                  value: localDays.toDouble(),
                  min: 0,
                  max: _maxTimeFilterDays.toDouble(),
                  divisions: _maxTimeFilterDays,
                  label: daysLabel(localDays),
                  onChanged: (v) {
                    setLocal(() {
                      localDays = v.round();
                      counts = computeCounts(); // refresh counts as the slider moves
                    });
                  },
                ),
                const SizedBox(height: 8),

                // chips for each category
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    chip(CrimeCategory.violent, 'Violent'),
                    chip(CrimeCategory.theft, 'Theft'),
                    chip(CrimeCategory.vehicle, 'Vehicle'),
                    chip(CrimeCategory.property, 'Property'),
                    chip(CrimeCategory.drug, 'Drug'),
                    chip(CrimeCategory.other, 'Other'),
                  ],
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    // reset filters button, (clears filters list and renders markers)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _activeFilters.clear();
                          _timeFilterDays = 0; // reset timeframe
                        });
                        _renderFilteredCrimes();
                      },
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    // Apply settings button (Task mentions a debouncer, after testing, a button is more logical)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _activeFilters = local;
                          _timeFilterDays = localDays; // commit timeframe
                        });
                        _renderFilteredCrimes();
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }


    // AI Assistant reccomended this method for 'jittering' when markers are atop eachother
    // Tried it out, looks more appealing than without

    //track how many markers occur at nearly the same coords
    final Map<String, int> _coordHitCounts = {};

    // if two markers occur on the same coords, count a 'hit' and adjust marker
    LatLng _jitterIfDuplicate(LatLng pos) {
      // Round so very close points are considered the same for stacking purposes.
      final key = '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}';
      final hit = (_coordHitCounts[key] ?? 0);
      _coordHitCounts[key] = hit + 1;

      if (hit == 0) return pos; // first marker stays exact

      // Spread overlapping pins in small rings around the original point.
      const double stepMeters = 6.0;                  // ≈6 m between rings
      final ring = 1 + (hit ~/ 6);                    // 6 markers per ring
      final slot = hit % 6;                           // position within the ring [0..5]
      final angle = (slot / 6.0) * 2 * math.pi;

      final rMeters = stepMeters * ring;

      // meters → degrees
      final dLat = rMeters / 111_111.0;
      final dLon = rMeters / (111_111.0 * math.cos(pos.latitude * math.pi / 180));

      return LatLng(
        pos.latitude  + dLat * math.sin(angle),
        pos.longitude + dLon * math.cos(angle),
      );
    }
      }
