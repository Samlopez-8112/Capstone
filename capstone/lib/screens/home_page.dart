// This screen is the 'main' screen of the app. Centers on user's current location
// UI should be added here

// See this tutorial for a better understanding: https://youtu.be/UafQ8rw1V-Y?si=kFv63X5jXPSJ4Vbl
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as gl; 
import 'package:permission_handler/permission_handler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

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

  @override
  Widget build(BuildContext context) { // screen is a scaffold with map widget and button
    return Scaffold(
      body: mb.MapWidget( // displays the map
        onMapCreated: _onMapCreated,
        ),
        floatingActionButton: FloatingActionButton( // button for toggling camera follow
          onPressed: () {
            setState(() {
              isFollowingUser = !isFollowingUser;
            });
          },
          child: Icon(
            isFollowingUser ? Icons.location_searching : Icons.location_disabled
          )
        )
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
}