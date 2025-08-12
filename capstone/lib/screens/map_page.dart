import 'dart:async';
import 'dart:math';

import 'package:capstone/screens/settings_screen.dart';
import 'package:capstone/screens/CrowdSource_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:url_launcher/url_launcher.dart';

import '../consts.dart';
import '../models/poi_category.dart';
import '../services/places_service.dart';
import '../widgets/autocomplete_search_bar.dart';
import 'friend_screen.dart';

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

  // Map overlays
  final Map<PolylineId, Polyline> polylines = {};
  final Map<MarkerId, Marker> markers = {};
  MarkerId? _searchMarkerId;

  // Nearby search state
  double _searchRadius = 2000;
  List<Map<String, dynamic>> _lastFetchedPOIs = [];

  // Example route ends (polyline demo)
  static const LatLng _origin = LatLng(32.5232, -92.6379); // ruston
  static const LatLng _destination = LatLng(32.5094, -92.1183); // monroe

  // ===== Heatmap state =====
  final Set<Circle> _heatCircles = {};
  bool _showHeatmap = true;
  Timer? _boundsDebounce;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ratingsSub;
  // maps each circleId to rating doc fields for the details bottom sheet
  final Map<CircleId, Map<String, dynamic>> _circleMeta = {};

  @override
  void initState() {
    super.initState();
    _checkUserAuthentication();
    getLocationUpdates().then((_) {
      getPolylinePoints().then(generatePolyline);
    });
    fixPinnedLocationData();
  }

  @override
  void dispose() {
    _boundsDebounce?.cancel();
    _ratingsSub?.cancel();
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
          ? const Center(child: CircularProgressIndicator())
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
                  onLongPress: _handleLongPressPin,
                  onTap: _onMapTap,
                ),

                // Search bar at the top
                Positioned(
                  top: 50,
                  left: 15,
                  right: 15,
                  child: AutocompleteSearchBar(
                    onSuggestionSelected: (LatLng coords) async {
                      final controller = await _mapController.future;
                      setState(() {
                        isFollowingUser = false;

                        // remove previous search marker if it exists
                        if (_searchMarkerId != null) {
                          markers.remove(_searchMarkerId);
                        }

                        final markerId = const MarkerId("search_temp");
                        _searchMarkerId = markerId;

                        // NOTE: We do NOT call _handleMarkerTap here because we
                        // don’t have a Places "place_id" for the free-form search coords
                        markers[markerId] = Marker(
                          markerId: markerId,
                          position: coords,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueCyan),
                          infoWindow:
                              const InfoWindow(title: "Searched Location"),
                        );
                      });

                      controller.animateCamera(
                        CameraUpdate.newLatLngZoom(coords, 13),
                      );
                    },
                  ),
                ),

                // Sign-out button
                Positioned(
                  top: 110,
                  right: 15,
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
                  bottom: 90,
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
                  bottom: 160,
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

                // Settings (gear) — top-left
                Positioned(
                  top: 50,
                  left: 10,
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
              ],
            ),
    );
  }

  // ===== Heatmap helpers (viewport streaming, color/intensity, details) =====

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

    final north =
        max(bounds.northeast.latitude, bounds.southwest.latitude);
    final south =
        min(bounds.northeast.latitude, bounds.southwest.latitude);
    final east =
        max(bounds.northeast.longitude, bounds.southwest.longitude);
    final west =
        min(bounds.northeast.longitude, bounds.southwest.longitude);

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

  // ===== Location / camera / polyline =====

  Future<void> getLocationUpdates() async {
    if (!await _location.serviceEnabled()) await _location.requestService();
    if (await _location.hasPermission() == PermissionStatus.denied) {
      await _location.requestPermission();
    }

    _location.onLocationChanged.listen((loc) {
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
    final result = await PolylinePoints().getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(_origin.latitude, _origin.longitude),
        destination: PointLatLng(_destination.latitude, _destination.longitude),
        mode: TravelMode.driving,
      ),
      googleApiKey: GOOGLE_MAPS_API_KEY,
    );
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

  // ===== POIs / Places =====

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

  // ===== Pinned / friends =====

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

  // ===== Utilities =====

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
}
