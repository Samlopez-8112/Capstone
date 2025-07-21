import 'dart:async';
import 'package:capstone/consts.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../widgets/autocomplete_search_bar.dart';
import '../services/places_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/friend_screen.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}


class _MapPageState extends State<MapPage> {
  Location _locationController = new Location();
  final Completer<GoogleMapController> _mapController = Completer<GoogleMapController>();
  LatLng? _currentP = null; //user's location
  Map<PolylineId, Polyline> polylines = {};
  bool isFollowingUser = true;
  Map<MarkerId, Marker> markers = {};

  static const LatLng _origin = LatLng(32.5232, -92.6379); // ruston
  static const LatLng _destination = LatLng(32.5094, -92.1183); // monroe

  @override
  void initState() {
    super.initState();
    getLocationUpdates().then(
      (_) => {
        getPolylinePoints().then((coordinates) => {
          generatePolyLineFromPoints(coordinates)
        }),
      },
    );
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: _currentP == null
        ? const Center(
            child: Text("Loading..."),
          )
        : Stack(
            children: [
              GoogleMap(
                onMapCreated: (GoogleMapController controller) {
                  _mapController.complete(controller);
                },
                initialCameraPosition: CameraPosition(
                  target: _currentP!,
                  zoom: 13,
                ),
                markers: Set<Marker>.of(markers.values),
                polylines: Set<Polyline>.of(polylines.values),
                onLongPress: _handleLongPressPin,
              ),

              // Search bar at the top ; instantiation of autocomplete_search_bar.dart
              Positioned(
                top: 50,
                left: 15,
                right: 15,
                child: AutocompleteSearchBar(
                  onSuggestionSelected: (LatLng coordinates) async {
                    final controller = await _mapController.future;
                    controller.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(target: coordinates, zoom: 13.0),
                      ),
                    );
                  },
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
              onPressed: () {
                setState(() => isFollowingUser = !isFollowingUser);
                if (isFollowingUser && _currentP != null) _cameraToPosition(_currentP!);
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FriendScreen()),
                );
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
             ),
            ],
          ),
  );
}


  Future<void> _cameraToPosition(LatLng pos) async {
    final GoogleMapController controller = await _mapController.future;
    CameraPosition _newCameraPosition = CameraPosition(
      target: pos,
      zoom: 13
    );
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(_newCameraPosition),
    );
  }

  Future<void> getLocationUpdates() async{
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _serviceEnabled = await _locationController.serviceEnabled();
    if (_serviceEnabled) {
      _serviceEnabled = await _locationController.requestService();
    } else {
      return;
    }

    _permissionGranted = await _locationController.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await _locationController.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    _locationController.onLocationChanged.listen((LocationData currentLocation) {
      if (currentLocation.latitude != null && currentLocation.longitude != null) {
        setState(() {
          _currentP = LatLng(currentLocation.latitude!, currentLocation.longitude!);
          _cameraToPosition(_currentP!);
        });
        if (isFollowingUser && _currentP != null) {
          _cameraToPosition(_currentP!); // move outside setState
        }
      }
    });
  }

  // makes the rout between two points
  Future<List<LatLng>> getPolylinePoints() async {
    List<LatLng> polylineCoordinates = [];
    PolylinePoints polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(_origin.latitude, _origin.longitude),
        destination: PointLatLng(_destination.latitude, _destination.longitude),
        mode: TravelMode.driving
      ),
      googleApiKey: GOOGLE_MAPS_API_KEY
    );
    if (result.points.isNotEmpty) {
      result.points.forEach((PointLatLng point) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });
    } else {
      print(result.errorMessage);
    }
    return polylineCoordinates;
  } 

  void generatePolyLineFromPoints(List<LatLng> polylineCoordinates) async {
    PolylineId id = PolylineId("poly");
    Polyline polyline = Polyline(
      polylineId: id, 
      color: Colors.blue, 
      points: polylineCoordinates, 
      width: 6);
    setState(() {
      polylines[id] = polyline;
    });
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

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pinned location saved!')));
  }

  void _showPinnedLocations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('pinned_locations')
        .orderBy('timestamp', descending: true)
        .get();

    final favorites = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['isFavorite'] == true;
    }).toList();

    final nonFavorites = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['isFavorite'] != true;
    }).take(3).toList();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: [
            const ListTile(title: Text("Favorite Locations")),
            ...favorites.map((doc) => _buildPinTile(doc, user.uid)),
            const Divider(),
            const ListTile(title: Text("Recent Locations")),
            ...nonFavorites.map((doc) => _buildPinTile(doc, user.uid)),
          ],
        );
      },
    );
  }

  Widget _buildPinTile(QueryDocumentSnapshot doc, String uid){
    final data = doc.data() as Map<String, dynamic>;
    final lat = doc['lat'];
    final lng = doc['lng'];
    final isFav = data['isFavorite'] == true;

    return ListTile(
      leading: Icon(isFav ? Icons.star : Icons.star_border),
      title: Text('Lat: $lat, Lng: $lng'),
      trailing: IconButton(
        icon: Icon(isFav ? Icons.star : Icons.star_border),
        onPressed: () {
          FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('pinned_locations')
            .doc(doc.id).update({'isFavorite' :!isFav});
          Navigator.pop(context);
          _showPinnedLocations();
        },
      ),
      onTap: (){
        Navigator.pop(context);
        _cameraToPosition(LatLng(lat, lng));
      }
    );
  }

  void _showSharingFriends() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('shared_locations')
      .where('isSharing', isEqualTo: true)
      .get();

  showModalBottomSheet(
    context: context,
    builder: (context) {
      return ListView(
        children: snapshot.docs.map((doc) {
          final friendUid = doc.id;

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(friendUid).get(),
            builder: (context, userSnap) {
              if (!userSnap.hasData || !userSnap.data!.exists) {
                return const ListTile(title: Text("Loading..."));
              }

              final displayName = userSnap.data!.get('displayName') ?? friendUid;

              return ListTile(
                leading: const Icon(Icons.person_pin_circle),
                title: Text(displayName),
                onTap: () async {
                  Navigator.pop(context);

                  final locSnap = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(friendUid)
                      .collection('location')
                      .doc('current')
                      .get();

                  if (!locSnap.exists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("$displayName has no location data.")),
                    );
                    return;
                  }

                  final lat = locSnap['lat'];
                  final lng = locSnap['lng'];
                  final friendPos = LatLng(lat, lng);

                  _cameraToPosition(friendPos);

                  // Add a temporary marker
                  final markerId = MarkerId("friend_$friendUid");
                  setState(() {
                    markers[markerId] = Marker(
                      markerId: markerId,
                      position: friendPos,
                      infoWindow: InfoWindow(title: displayName),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
                    );
                  });

                  // Remove after 5 seconds
                  Future.delayed(Duration(seconds: 5), () {
                    setState(() {
                      markers.remove(markerId);
                    });
                  });
                },
              );
            },
          );
        }).toList(),
      );
    },
  );
}

}