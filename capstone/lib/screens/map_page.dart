import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
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
  LatLng? _currentPosition;
  bool isFollowingUser = true;

  Map<PolylineId, Polyline> polylines = {};
  Map<MarkerId, Marker> markers = {};
  MarkerId? _searchMarkerId;

  double _searchRadius = 2000;
  List<Map<String, dynamic>> _lastFetchedPOIs = [];

  static const LatLng _origin = LatLng(32.5232, -92.6379);
  static const LatLng _destination = LatLng(32.5094, -92.1183);

  @override
  void initState() {
    super.initState();
    getLocationUpdates().then((_) {
      getPolylinePoints().then(generatePolyline);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _currentPosition!,
                  zoom: 13,
                ),
                myLocationEnabled: true,
                markers: Set<Marker>.of(markers.values),
                polylines: Set<Polyline>.of(polylines.values),
                onMapCreated: (controller) => _mapController.complete(controller),
                onLongPress: _handleLongPressPin,
              ),
              Positioned(
                top: 50,
                left: 15,
                right: 15,
                child: AutocompleteSearchBar(
                  onSuggestionSelected: (LatLng coords) async {
                    final controller = await _mapController.future;
                    setState(() {
                      isFollowingUser = false;
                      if (_searchMarkerId != null) {
                        markers.remove(_searchMarkerId);
                      }
                      final markerId = MarkerId("search_temp");
                      _searchMarkerId = markerId;
                      markers[markerId] = Marker(
                        markerId: markerId,
                        position: coords,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
                        infoWindow: const InfoWindow(title: "Searched Location"),
                      );
                    });
                    controller.animateCamera(CameraUpdate.newLatLngZoom(coords, 13));
                  },
                ),
              ),
              Positioned(
                top: 110,
                right: 15,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 4),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Icon(Icons.logout),
                ),
              ),
              Positioned(
                bottom: 160,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black26)]),
                  child: Column(
                    children: [
                      const Text("Search Radius (m)", style: TextStyle(fontWeight: FontWeight.bold)),
                      Slider(
                        value: _searchRadius,
                        min: 100,
                        max: 5000,
                        divisions: 49,
                        label: '${_searchRadius.round()}m',
                        onChanged: (value) => setState(() => _searchRadius = value),
                      )
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 90,
                left: 20,
                child: SpeedDial(
                  icon: Icons.place,
                  activeIcon: Icons.close,
                  backgroundColor: Colors.blueAccent,
                  spacing: 12,
                  children: PoiCategory.values.map((cat) {
                    return SpeedDialChild(
                      child: Image.asset(cat.iconPath, height: 24),
                      label: cat.label,
                      onTap: () => _fetchCategoryPOIs(cat),
                    );
                  }).toList(),
                ),
              ),
              Positioned(
                bottom: 90,
                right: 20,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      isFollowingUser = !isFollowingUser;
                      if (isFollowingUser && _searchMarkerId != null) {
                        markers.remove(_searchMarkerId);
                        _searchMarkerId = null;
                      }
                    });
                    if (isFollowingUser && _currentPosition != null) {
                      _cameraTo(_currentPosition!);
                    }
                  },
                  child: Icon(isFollowingUser ? Icons.my_location : Icons.location_disabled),
                ),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton(
                  onPressed: _showPinnedLocations,
                  child: const Icon(Icons.bookmark),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendScreen()));
                  },
                  child: const Text("Friends"),
                ),
              ),
              Positioned(
                bottom: 160,
                left: 20,
                child: FloatingActionButton(
                  onPressed: _showSharingFriends,
                  child: const Icon(Icons.people),
                ),
              )
            ]),
    );
  }

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
    final id = PolylineId("poly");
    polylines[id] = Polyline(
      polylineId: id,
      color: Colors.blue,
      width: 6,
      points: coordinates,
    );
    setState(() {});
  }

  Future<void> _handleLongPressPin(LatLng pos) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

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
        markers.removeWhere((key, marker) => marker.infoWindow.title?.contains('POI') ?? false);
        for (final poi in results) {
          final lat = poi['geometry']['location']['lat'];
          final lng = poi['geometry']['location']['lng'];
          final markerId = MarkerId(poi['place_id'] ?? '$lat$lng');
          markers[markerId] = Marker(
            markerId: markerId,
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: poi['name'] ?? 'POI',
              snippet: poi['vicinity'] ?? '',
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
    final sorted = [..._lastFetchedPOIs]..sort((a, b) {
        final aLat = a['geometry']['location']['lat'];
        final aLng = a['geometry']['location']['lng'];
        final bLat = b['geometry']['location']['lat'];
        final bLng = b['geometry']['location']['lng'];
        return _calculateDistanceMeters(_currentPosition!, aLat, aLng)
            .compareTo(_calculateDistanceMeters(_currentPosition!, bLat, bLng));
      });

    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final poi = sorted[i];
          final lat = poi['geometry']['location']['lat'];
          final lng = poi['geometry']['location']['lng'];
          return ListTile(
            leading: const Icon(Icons.location_on),
            title: Text(poi['name'] ?? 'Unknown'),
            subtitle: Text('${poi['vicinity'] ?? 'No address'} • ${_calculateDistanceMeters(_currentPosition!, lat, lng).round()}m'),
            trailing: IconButton(
              icon: const Icon(Icons.navigation),
              onPressed: () => _launchNavigation(lat, lng),
            ),
            onTap: () async {
              final controller = await _mapController.future;
              controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  double _calculateDistanceMeters(LatLng from, double lat2, double lng2) {
    const R = 6371000;
    final dLat = (lat2 - from.latitude) * (pi / 180);
    final dLng = (lng2 - from.longitude) * (pi / 180);
    final a = 0.5 - cos(dLat) / 2 +
        cos(from.latitude * pi / 180) *
            cos(lat2 * pi / 180) *
            (1 - cos(dLng)) / 2;
    return R * 2 * asin(sqrt(a));
  }

  Future<void> _launchNavigation(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch Google Maps.')),
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

  Future<void> _showSharingFriends() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

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

              final lat = loc['lat'];
              final lng = loc['lng'];
              final pos = LatLng(lat, lng);
              _cameraTo(pos);

              final id = MarkerId("friend_${doc.id}");
              setState(() {
                markers[id] = Marker(
                  markerId: id,
                  position: pos,
                  infoWindow: InfoWindow(title: displayName),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
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
}
