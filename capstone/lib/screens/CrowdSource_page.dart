//Assistance from ChatGpt

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RateAreaScreen extends StatefulWidget {
  final LatLng? pos;

  const RateAreaScreen({Key? key, this.pos}) : super(key: key);

  @override
  State<RateAreaScreen> createState() => _RateAreaScreenState();
}

class _RateAreaScreenState extends State<RateAreaScreen> {
  String _personalExperienceText = "";
  final _reasonsMaster = const [
    'Well-lit',
    'Police presence',
    'Quiet at night',
    'Busy foot traffic',
    'Loitering',
    'Graffiti/vandalism',
    'Poor lighting',
    'Suspicious activity',
    'Reports of crime',
    'Clean and maintained',
    'Security cameras',
    'Poor lighting',
    'Active neighborhood watch',
    'Nearby schools or parks',
    'Frequent police sirens',
    'Abandoned buildings',
    'Shops open late',
    'Personal experience',
  ];

  // Step state
  Map<String, dynamic>? _selectedPin; // {lat, lng, timestamp}
  double _radiusMiles = 0.5;          // 0 – 2 miles
  double _rating = 3;                 // 1 – 5
  final Set<String> _selectedReasons = {};

  @override
  void initState(){
    super.initState();

    //if a location is passed from the map long-press, set it immediately
    if(widget.pos != null){
      _selectedPin = {
        'lat': widget.pos!.latitude,
        'lng': widget.pos!.longitude,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to rate areas.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Community Rating')),
      body: _selectedPin == null
          ? _buildPinnedLocationsStep(user.uid)
          : _buildRatingFormStep(user.uid),
    );
  }

  /// STEP 1: Choose from user's pinned locations
  Widget _buildPinnedLocationsStep(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pinned_locations')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'No pinned locations yet.\nLong-press the map to pin one, then come back!',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final docs = snap.data!.docs;
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final lat = d['lat'] as num?;
            final lng = d['lng'] as num?;
            final ts = (d['timestamp'] as Timestamp?)?.toDate();
            if (lat == null || lng == null) return const SizedBox.shrink();
            return ListTile(
              leading: const Icon(Icons.location_pin),
              title: Text('Lat ${lat.toStringAsFixed(5)}, Lng ${lng.toStringAsFixed(5)}'),
              subtitle: Text(ts != null ? 'Pinned at $ts' : 'Pinned'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                setState(() {
                  _selectedPin = {'lat': lat.toDouble(), 'lng': lng.toDouble()};
                });
              },
            );
          },
        );
      },
    );
  }

  /// STEP 2: Radius + Rating + Reasons
  Widget _buildRatingFormStep(String uid) {
    final lat = _selectedPin!['lat'] as double;
    final lng = _selectedPin!['lng'] as double;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedPin = null),
                tooltip: 'Choose a different pin',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Selected: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Radius slider 0–2 miles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Radius'),
              Text('${_radiusMiles.toStringAsFixed(2)} mi'),
            ],
          ),
          Slider(
            min: 0.0,
            max: 2.0,
            divisions: 20, // 0.1 mi steps
            value: _radiusMiles,
            label: '${_radiusMiles.toStringAsFixed(2)} mi',
            onChanged: (v) => setState(() => _radiusMiles = v),
          ),
          const SizedBox(height: 8),

          // Rating slider 1–5
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Safety rating'),
              Text(_rating.toStringAsFixed(1)),
            ],
          ),
          Slider(
            min: 1,
            max: 5,
            divisions: 4,
            value: _rating,
            label: _rating.toStringAsFixed(0),
            onChanged: (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 8),

          // Reasons multi-select
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Reasons (select all that apply):'),
          ),
          const SizedBox(height: 8),
          Expanded(
          child: ListView(
          children: _reasonsMaster.map((r) {
          final selected = _selectedReasons.contains(r);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                dense: true,
                value: selected,
                title: Text(r),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedReasons.add(r);
                    } else {
                      _selectedReasons.remove(r);
                    if (r == "Personal experience") {
                      _personalExperienceText = ""; // clear input
                    }
                    }
                  });
                },
              ),
              if (r == "Personal experience" && selected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: "Please explain your personal experience",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    _personalExperienceText = val;
                  },
                ),
              ),
            ],
          );
        }).toList(),
      ),
    ),

          // Save
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save rating'),
              onPressed: () => _saveRating(uid, lat, lng),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRating(String uid, double lat, double lng) async {
    // Build a location key that includes radius; you can swap this for geohash+radius
    final locationKey =
        "${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}:r=${_radiusMiles.toStringAsFixed(2)}mi";

    // One rating per user per (locationKey)
    final ratingDoc = FirebaseFirestore.instance
        .collection('crowdRatings')
        .doc(locationKey)
        .collection('ratings')
        .doc(uid);

    await ratingDoc.set({
      'userId': uid,
      'center': {'lat': lat, 'lng': lng},
      'radiusMiles': _radiusMiles,
      'rating': _rating,
      'reasons': _selectedReasons.toList(),
      'personalExperienceDetail': _personalExperienceText.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks! Your rating was saved.')),
    );
  }
}
