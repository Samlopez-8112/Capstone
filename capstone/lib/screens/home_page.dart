// This screen is the 'main' screen of the app. Centers on user's current location
// UI should be added here

// See this tutorial for a better understanding: https://youtu.be/UafQ8rw1V-Y?si=kFv63X5jXPSJ4Vbl
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as gl; 
import 'package:permission_handler/permission_handler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:capstone/widgets/saved_location_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


// imports for mapbox and geolocator must be 'as xx' because they share some function names
class HomePage extends StatefulWidget { 
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {

  mb.MapboxMap? mapboxMapController; //mapbox controller is an instance of map
  StreamSubscription? userPositionStream; // used for GPS updates
  bool isFollowingUser = true; // option for camera following

  final TextEditingController _searchController = TextEditingController();

  void _handleSearch(String query) {
    // TODO: Blend mapbox geocoding for searches
    debugPrint('Searching for: $query');
  }

  @override
  void initState() {
 
    super.initState(); 
    _setupPositionTracking(); // set up position tracking on initialization
  }

  @override
  void dispose(){
    userPositionStream?.cancel(); // cancel the position tracking when not in use
    super.dispose();
  }

  // Build the layout
  @override
  Widget build(BuildContext context) {
    return Scaffold( // scaffold style layout
      body:Stack( //stack contains search bar and mapbox widget
        children: [
          mb.MapWidget( //call map at beginning of stack and setup
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
            child: Container( // white bar positioned at top of screen
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black26)],
              ),
              child: TextField( // text field within box
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
          // Sign out button
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
          // This is the new button here:
              Positioned(
                bottom: 20,
                right: 20,
                child: SavedLocationButton(onPressed: _showPinnedLocations),               
    ),
        ],
      ),
    );
  }

  void _onMapCreated( // call this function when map is created
                      // handles permissions and location marker
    mb.MapboxMap controller,
    ) async {
    setState(() {
        mapboxMapController = controller;
    });

    var status = await Permission.location.request(); // wait for location permissions to place location icon
    if (status.isGranted) {
    mapboxMapController?.location.updateSettings(
      mb.LocationComponentSettings( // place the location puck
      enabled:true,
      pulsingEnabled:true,
      ),
    );
    } else {
      debugPrint("Location permissions denied.");
    }
    void _onMapCreated(mb.MapboxMap controller) {
  setState(() {
    mapboxMapController = controller;
  });
  
  controller.addInteraction(
    mb.LongTapInteraction.onMap((ctx) {
      final lat = (ctx.point.coordinates[1] as num).toDouble();
      final lng = (ctx.point.coordinates[0] as num).toDouble();
      _handleLongPressPin(lat, lng);
    })
  );
  
}

  }

  Future<void> _setupPositionTracking() async{
    bool serviceEnabled;
    gl.LocationPermission permission; 
    serviceEnabled = await gl.Geolocator.isLocationServiceEnabled(); // check if location services are allowed

    // error codes for various levels of location permission status
    if(!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }
    permission = await gl.Geolocator.checkPermission();
    if (permission == gl.LocationPermission.denied) {
      permission = await gl.Geolocator.requestPermission(); //request permissions again if they weren't given
      if (permission == gl.LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    if (permission == gl.LocationPermission.deniedForever){
      return Future.error('User permanently denied permissions');
    }

    gl.LocationSettings locationSettings = gl.LocationSettings( //setup geolocator settings
      accuracy: gl.LocationAccuracy.high,
      distanceFilter: 10, // how far should a user move before adjusting (in meters)
      );

      userPositionStream?.cancel();
      userPositionStream = 
      gl.Geolocator.getPositionStream(locationSettings: locationSettings) //start geolocator
          .listen(
        (gl.Position? position,) {
          if(position != null && mapboxMapController != null && isFollowingUser) {
            mapboxMapController?.flyTo( //flying visual when adjusting camera
              mb.CameraOptions(
                center: mb.Point(coordinates: mb.Position( //center camera on current coordinates
                  position.longitude,
                  position.latitude,
                  ),
                  ),
                  zoom: 15, // zoom level 15; may want closer for navigation
              ),
             mb.MapAnimationOptions(duration: 500), //flyto animation takes 500ms
            );
          }
        },
      );
  }
  //logic to display pinned locations
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
                  center: mb.Point(
                    coordinates: mb.Position(lng, lat),
                  ),
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
//long press logic
Future<void> _handleLongPressPin(double lat, double lng) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('pinned_locations')
      .add({
        'lat': lat.toDouble(),
        'lng': lng.toDouble(),
        'timestamp': FieldValue.serverTimestamp(),
      });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Pinned location saved!')),
  );
}

}
//Changed button style to match purpose
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
