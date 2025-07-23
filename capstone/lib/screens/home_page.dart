// This screen is the 'main' screen of the app. Centers on user's current location
// UI should be added here

// See this tutorial for a better understanding: https://youtu.be/UafQ8rw1V-Y?si=kFv63X5jXPSJ4Vbl
import 'dart:async';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:permission_handler/permission_handler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:capstone/widgets/saved_location_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/friend_screen.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:flutter_speed_dial/flutter_speed_dial.dart'; 
import 'package:capstone/models/poi_category.dart' show PoiCategory;
import 'package:capstone/services/places_service.dart' as places;
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  mb.MapboxMap? mapboxMapController;
  StreamSubscription? userPositionStream;
  bool isFollowingUser = true;
  final TextEditingController _searchController = TextEditingController();
  double _searchRadius = 2000;
  List<Map<String, dynamic>> _lastFetchedPOIs = [];

  void _handleSearch(String query) {
    debugPrint('Searching for: $query');
  }

  @override
  void initState() {
    super.initState();
    _setupPositionTracking();
  }

  @override
  void dispose() {
    userPositionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          mb.MapWidget(
            onMapCreated: _onMapCreated,
            onLongTapListener: (mb.MapContentGestureContext ctx) {
              final lat = (ctx.point.coordinates[1] as num).toDouble();
              final lng = (ctx.point.coordinates[0] as num).toDouble();
              _handleLongPressPin(lat, lng);
            },
          ),
          Positioned(
            top: 50,
            left: 15,
            right: 15,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black26)],
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: _handleSearch,
                decoration: InputDecoration(
                  hintText: 'Search',
                  border: InputBorder.none,
                  suffixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          Positioned(
            top: 110,
            right: 15,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 4,
                padding: const EdgeInsets.all(10),
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Icon(Icons.logout),
            ),
          ),
          Positioned(
            bottom: 90,
            right: 20,
            child: FloatingActionButton(
              elevation: 4,
              onPressed: () async {
                setState(() {
                  isFollowingUser = !isFollowingUser;
                });

                if (isFollowingUser && mapboxMapController != null) {
                  try {
                    final position = await gl.Geolocator.getCurrentPosition(
                      desiredAccuracy: gl.LocationAccuracy.high,
                    );
                    mapboxMapController!.flyTo(
                      mb.CameraOptions(
                        center: mb.Point(
                          coordinates: mb.Position(
                            position.longitude,
                            position.latitude,
                          ),
                        ),
                        zoom: 16,
                      ),
                      mb.MapAnimationOptions(duration: 500),
                    );
                  } catch (e) {
                    debugPrint('Error getting current position: $e');
                  }
                }
              },
              child: Icon(
                isFollowingUser ? Icons.my_location : Icons.location_disabled,
              ),
            ),
          ),
          // Radius Slider
          Positioned(
            bottom: 160,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black26)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Search Radius (m)", style: TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _searchRadius,
                    min: 100,
                    max: 5000,
                    divisions: 49,
                    label: '${_searchRadius.round()}m',
                    onChanged: (value) {
                      setState(() {
                        _searchRadius = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          // Speed Dial
          Positioned(
            bottom: 90,
            left: 20,
            child: SpeedDial(
              icon: Icons.place,
              activeIcon: Icons.close,
              backgroundColor: Colors.blueAccent,
              spacing: 12,
              spaceBetweenChildren: 8,
              overlayColor: Colors.black,
              overlayOpacity: 0.3,
              children: [
                SpeedDialChild(
                  child: const Icon(Icons.local_hospital),
                  label: 'Hospitals',
                  onTap: () => _fetchCategoryPOIs(PoiCategory.hospital),
                ),
                SpeedDialChild(
                  child: const Icon(Icons.local_gas_station),
                  label: 'Gas Stations',
                  onTap: () => _fetchCategoryPOIs(PoiCategory.gasStation),
                ),
                SpeedDialChild(
                  child: const Icon(Icons.local_police),
                  label: 'Police Stations',
                  onTap: () => _fetchCategoryPOIs(PoiCategory.police),
                ),
                SpeedDialChild(
                  child: const Icon(Icons.build),
                  label: 'Mechanics',
                  onTap: () => _fetchCategoryPOIs(PoiCategory.carRepair),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: SavedLocationButton(onPressed: _showPinnedLocations),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FriendScreen()),
                );
              },
              child: const Text("Friends"),
            ),
          ),
        ],
      ),
    );
  }

  void _onMapCreated(mb.MapboxMap controller) async {
    setState(() {
      mapboxMapController = controller;
    });

    var status = await Permission.location.request();
    if (status.isGranted) {
      mapboxMapController?.location.updateSettings(
        mb.LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
        ),
      );
    } else {
      debugPrint("Location permissions denied.");
    }
  }

  Future<void> _setupPositionTracking() async {
    bool serviceEnabled;
    gl.LocationPermission permission;

    serviceEnabled = await gl.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    permission = await gl.Geolocator.checkPermission();
    if (permission == gl.LocationPermission.denied) {
      permission = await gl.Geolocator.requestPermission();
      if (permission == gl.LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    if (permission == gl.LocationPermission.deniedForever) {
      return Future.error('User permanently denied permissions');
    }

    gl.LocationSettings locationSettings = gl.LocationSettings(
      accuracy: gl.LocationAccuracy.high,
      distanceFilter: 10,
    );

    userPositionStream?.cancel();
    userPositionStream = gl.Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((gl.Position? position) {
      if (position != null && mapboxMapController != null && isFollowingUser) {
        mapboxMapController?.flyTo(
          mb.CameraOptions(
            center: mb.Point(coordinates: mb.Position(
              position.longitude,
              position.latitude,
            )),
            zoom: 16,
          ),
          mb.MapAnimationOptions(duration: 500),
        );
      }
    });
  }

  void _showPinnedLocations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('pinned_locations')
        .orderBy('timestamp', descending: true)
        .limit(5)
        .get();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: snapshot.docs.map((doc) {
            final lat = doc['lat'];
            final lng = doc['lng'];
            final time = doc['timestamp']?.toDate().toString() ?? 'Unknown time';
            return ListTile(
              leading: Icon(Icons.location_pin),
              title: Text('Lat: $lat, Lng: $lng'),
              subtitle: Text('Pinned at $time'),
              onTap: () {
                Navigator.pop(context);
                mapboxMapController?.flyTo(
                  mb.CameraOptions(
                    center: mb.Point(coordinates: mb.Position(lng, lat)),
                    zoom: 15,
                  ),
                  mb.MapAnimationOptions(duration: 500),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _handleLongPressPin(double lat, double lng) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('pinned_locations')
        .add({
          'lat': lat,
          'lng': lng,
          'timestamp': FieldValue.serverTimestamp(),
        });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pinned location saved!')),
    );
  }

  Future<void> _fetchCategoryPOIs(PoiCategory category) async {
    try {
      final userPos = await gl.Geolocator.getCurrentPosition();
      final results = await places.NearbyPlacesService().fetchNearby(
        latitude: userPos.latitude,
        longitude: userPos.longitude,
        category: category,
        radius: _searchRadius.round(),
      );

      setState(() {
        _lastFetchedPOIs = results;
      });

      _showPOIListSheet(userPos.latitude, userPos.longitude);
    } catch (e) {
      debugPrint('Error fetching ${category.label}: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch ${category.label} nearby')),
      );
    }
  }

  void _showPOIListSheet(double userLat, double userLng) {
    final sorted = List<Map<String, dynamic>>.from(_lastFetchedPOIs);
    sorted.sort((a, b) {
      final aLat = a['geometry']['location']['lat'];
      final aLng = a['geometry']['location']['lng'];
      final bLat = b['geometry']['location']['lat'];
      final bLng = b['geometry']['location']['lng'];
      final distA = _calculateDistanceMeters(userLat, userLng, aLat, aLng);
      final distB = _calculateDistanceMeters(userLat, userLng, bLat, bLng);
      return distA.compareTo(distB);
    });

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final poi = sorted[index];
            final name = poi['name'] ?? 'Unknown';
            final vicinity = poi['vicinity'] ?? 'Address not found';
            final lat = poi['geometry']['location']['lat'];
            final lng = poi['geometry']['location']['lng'];
            final distance = _calculateDistanceMeters(userLat, userLng, lat, lng).round();

            return ListTile(
              leading: Icon(Icons.location_on),
              title: Text(name),
              subtitle: Text('$vicinity • $distance m'),
              trailing: IconButton(
                icon: Icon(Icons.navigation),
                onPressed: () => _launchNavigation(lat, lng),
              ),
              onTap: () {
                Navigator.pop(context);
                mapboxMapController?.flyTo(
                  mb.CameraOptions(
                    center: mb.Point(coordinates: mb.Position(lng, lat)),
                    zoom: 15,
                  ),
                  mb.MapAnimationOptions(duration: 500),
                );
              },
            );
          },
        );
      },
    );
  }

  double _calculateDistanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLng = (lng2 - lng1) * (pi / 180);
    final a = 0.5 - cos(dLat)/2 + cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * (1 - cos(dLng))/2;
    return R * 2 * asin(sqrt(a));
  }

  Future<void> _launchNavigation(double destLat, double destLng) async {
    final Uri googleUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving',
    );

    if (await canLaunchUrl(googleUri)) {
      await launchUrl(googleUri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch Google Maps.')),
      );
    }
  }
}

class SavedLocationButton extends StatelessWidget {
  final VoidCallback onPressed;
  const SavedLocationButton({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      child: Icon(Icons.bookmark),
    );
  }
}
