import 'package:capstone/screens/auth_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';


import '../screens/home_page.dart';
void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await setup();
  runApp(const MyApp());
}

Future<void> setup() async{
  await dotenv.load( // grab .env from discord, name ".env", and insert it in the project directory (alongside pubspec.yaml)
    fileName: "envy",
  );
  MapboxOptions.setAccessToken(
    dotenv.env["MAPBOX_ACCESS_TOKEN"]!, // .env contains api tokens
    );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot){
          if(snapshot.connectionState == ConnectionState.waiting){
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }else if (snapshot.hasData){
            return const HomePage();
          }else{
            return const AuthScreen();
          }
        })
    );
  }
}

// Speed Dial widget, still unfinished and left ti integrate with firebase or superbase that we use
class LocationSpeedDial extends StatelessWidget {
  const LocationSpeedDial({super.key});

  void _handleTap(BuildContext context, String type) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Marking location as $type')),
    );
    // TO DO: integrate with map and Firebase
  }

  @override
  Widget build(BuildContext context) {
    return SpeedDial(
      icon: Icons.place,
      activeIcon: Icons.close,
      backgroundColor: Colors.blueAccent,
      spacing: 12,
      children: [
        SpeedDialChild(
          child: const Icon(Icons.home),
          label: 'Mark as Home',
          onTap: () => _handleTap(context, 'Home'),
        ),
        SpeedDialChild(
          child: const Icon(Icons.work),
          label: 'Mark as Work',
          onTap: () => _handleTap(context, 'Work'),
        ),
        SpeedDialChild(
          child: const Icon(Icons.star),
          label: 'Add to Favourites',
          onTap: () => _handleTap(context, 'Favourite'),
        ),
        SpeedDialChild(
          child: const Icon(Icons.push_pin),
          label: 'Pin Location',
          onTap: () => _handleTap(context, 'Pin'),
        ),
      ],
    );
  }
}