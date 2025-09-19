import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestLocationPermission(BuildContext context) async {
  var status = await Permission.location.status;
  if (status.isGranted) return true;

  if (status.isPermanentlyDenied) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Location Permission"),
        content: const Text("Location access is permanently denied. Please enable it in your app settings."),
        actions: [
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(ctx).pop();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
    return false;
  }

  status = await Permission.location.request();
  return status.isGranted;
}
