import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:capstone/consts.dart';
import 'package:capstone/services/places_service.dart';
import 'package:capstone/models/poi_category.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  Location _location = Location();
  final Completer<GoogleMapController> _mapController = Completer();
  LatLng? _currentPosition;
  Set<Marker> _markers = {};
  double _searchRadius = 2000;
  List<Map<String, dynamic>> _lastFetchedPOIs = [];
  Map<PolylineId, Polyline> polylines = {};

  static const LatLng _origin = LatLng(32.5232, -92.6379);
  static const LatLng _destination = LatLng(32.5094, -92.1183);

  @override
  void initState() {
    super.initState();
    getLocationUpdates().then((_) {
      getPolylinePoints().then((coords) {
        generatePolyline(coords);
      });
    });
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
                  myLocationButtonEnabled: false,
                  onMapCreated: (controller) => _mapController.complete(controller),
                  markers: _markers,
                  polylines: Set<Polyline>.of(polylines.values),
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
                            setState(() => _searchRadius = value);
                          },
                        ),
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
                    spaceBetweenChildren: 8,
                    overlayColor: Colors.black,
                    overlayOpacity: 0.3,
                    children: PoiCategory.values.map((cat) {
                      return SpeedDialChild(
                        child: Image.asset(cat.iconPath, height: 24),
                        label: cat.label,
                        onTap: () => _fetchCategoryPOIs(cat),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> getLocationUpdates() async {
    final permission = await _location.requestPermission();
    final service = await _location.requestService();

    if (permission != PermissionStatus.granted || !service) return;

    _location.onLocationChanged.listen((locationData) async {
      if (locationData.latitude != null && locationData.longitude != null) {
        final pos = LatLng(locationData.latitude!, locationData.longitude!);
        setState(() => _currentPosition = pos);
        final controller = await _mapController.future;
        controller.animateCamera(CameraUpdate.newLatLng(pos));
      }
    });
  }

  Future<List<LatLng>> getPolylinePoints() async {
    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(_origin.latitude, _origin.longitude),
        destination: PointLatLng(_destination.latitude, _destination.longitude),
        mode: TravelMode.driving,
      ),
      googleApiKey: GOOGLE_MAPS_API_KEY,
    );
    if (result.points.isNotEmpty) {
      polylineCoordinates = result.points
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    } else {
      debugPrint("Polyline error: ${result.errorMessage}");
    }
    return polylineCoordinates;
  }

  void generatePolyline(List<LatLng> coordinates) {
    final id = PolylineId("route");
    final polyline = Polyline(
      polylineId: id,
      color: Colors.blue,
      points: coordinates,
      width: 6,
    );
    setState(() {
      polylines[id] = polyline;
    });
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

      Set<Marker> newMarkers = results.map((place) {
        final lat = place['geometry']['location']['lat'];
        final lng = place['geometry']['location']['lng'];
        return Marker(
          markerId: MarkerId(place['place_id']),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: place['name'] ?? 'No Name',
            snippet: place['vicinity'] ?? '',
            onTap: () => _launchNavigation(lat, lng),
          ),
        );
      }).toSet();

      setState(() {
        _lastFetchedPOIs = results;
        _markers = newMarkers;
      });

      _showPOIListSheet(); // 👈 Show list after fetch
    } catch (e) {
      debugPrint('Error fetching ${category.label}: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch ${category.label} nearby')),
      );
    }
  }

  void _showPOIListSheet() {
    if (_currentPosition == null || _lastFetchedPOIs.isEmpty) return;

    final sorted = List<Map<String, dynamic>>.from(_lastFetchedPOIs);
    sorted.sort((a, b) {
      final aLat = a['geometry']['location']['lat'];
      final aLng = a['geometry']['location']['lng'];
      final bLat = b['geometry']['location']['lat'];
      final bLng = b['geometry']['location']['lng'];
      final distA = _calculateDistanceMeters(_currentPosition!.latitude, _currentPosition!.longitude, aLat, aLng);
      final distB = _calculateDistanceMeters(_currentPosition!.latitude, _currentPosition!.longitude, bLat, bLng);
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
            final vicinity = poi['vicinity'] ?? 'No address';
            final lat = poi['geometry']['location']['lat'];
            final lng = poi['geometry']['location']['lng'];
            final distance = _calculateDistanceMeters(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng).round();

            return ListTile(
              leading: const Icon(Icons.location_on),
              title: Text(name),
              subtitle: Text('$vicinity • $distance m'),
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

  Future<void> _launchNavigation(double lat, double lng) async {
    final Uri googleUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(googleUri)) {
      await launchUrl(googleUri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch Google Maps.')),
      );
    }
  }
}
