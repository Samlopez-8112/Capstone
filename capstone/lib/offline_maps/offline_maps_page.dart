// lib/offline_maps/offline_maps_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';

class OfflineMapsPage extends StatefulWidget {
  const OfflineMapsPage({super.key});

  @override
  State<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends State<OfflineMapsPage> {
  // ---- CONFIG ----
  static const int minZoom = 12;
  static const int maxZoom = 16;
  static const int tileSizeBytesGuess = 24 * 1024; // ~24 KB avg per tile
  static const int concurrency = 8;

  late final Dio _dio;
  GoogleMapController? _map;

  CameraPosition _camera = const CameraPosition(
    target: LatLng(32.5232, -92.6379), // Ruston-ish
    zoom: 12,
  );

  // Selection radius stored in miles
  double _radiusMiles = 5.0;
  double get _radiusMeters => _radiusMiles * 1609.34;

  bool _downloading = false;
  int _estTiles = 0;
  double _estMB = 0;

  // Saved toggle
  bool _saved = false;

  // POIs
  bool _showPois = true;
  String? _poiFilter;
  Set<Marker> _poiMarkers = {};

  // Storage
  late Directory _root;
  late Directory _tilesRoot;
  late Directory _poisRoot;
  late File _packsFile;

  // Packs
  final List<_OfflinePack> _packs = [];

  String get _mapTilerKey => dotenv.env['MAPTILER_KEY'] ?? '';
  String _tileUrl(int z, int x, int y) =>
      'https://api.maptiler.com/tiles/streets/$z/$x/$y.png?key=$_mapTilerKey';

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
    _prepareStorage().then((_) async {
      await _loadPacks();
      _recomputeEstimates();
      setState(() {});
    });
  }

  // ---------- Storage ----------
  Future<void> _prepareStorage() async {
    final dir = await getApplicationSupportDirectory();
    _root = Directory('${dir.path}/offline');
    _tilesRoot = Directory('${_root.path}/tiles');
    _poisRoot = Directory('${_root.path}/pois');
    _packsFile = File('${_root.path}/packs.json');
    await _tilesRoot.create(recursive: true);
    await _poisRoot.create(recursive: true);
    if (!await _packsFile.exists()) {
      await _packsFile.writeAsString(jsonEncode({'packs': []}));
    }
  }

  Future<void> _loadPacks() async {
    try {
      final txt = await _packsFile.readAsString();
      final map = jsonDecode(txt) as Map<String, dynamic>;
      final lst =
          (map['packs'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      _packs
        ..clear()
        ..addAll(lst.map(_OfflinePack.fromJson));
    } catch (_) {
      _packs.clear();
      await _packsFile.writeAsString(jsonEncode({'packs': []}));
    }
  }

  Future<void> _savePacks() async {
    final map = {'packs': _packs.map((p) => p.toJson()).toList()};
    await _packsFile.writeAsString(jsonEncode(map));
  }

  // ---------- Geometry ----------
  static double _degToRad(double d) => d * math.pi / 180.0;
  static double _radToDeg(double r) => r * 180.0 / math.pi;
  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2.0;

  LatLngBounds _circleBounds(LatLng center, double meters) {
    final dLat = meters / 111_320.0;
    final mPerDegLon = 111_320.0 * math.cos(_degToRad(center.latitude).abs());
    final dLon = meters / (mPerDegLon == 0 ? 1 : mPerDegLon);
    return LatLngBounds(
      southwest: LatLng(center.latitude - dLat, center.longitude - dLon),
      northeast: LatLng(center.latitude + dLat, center.longitude + dLon),
    );
  }

  static int _long2tileX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();
  static int _lat2tileY(double lat, int z) {
    final rad = _degToRad(lat);
    return ((1 -
                math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
            2 *
            (1 << z))
        .floor();
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final la1 = _degToRad(a.latitude);
    final la2 = _degToRad(b.latitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * R * math.asin(math.sqrt(h));
  }

  bool _tileCenterInCircle({
    required int z,
    required int x,
    required int y,
    required LatLng center,
    required double radiusMeters,
  }) {
    final n = math.pi - (2.0 * math.pi * y) / math.pow(2.0, z);
    final lon = x / math.pow(2.0, z) * 360.0 - 180.0;
    final lat = _radToDeg(math.atan(_sinh(n)));
    return _haversineMeters(center, LatLng(lat, lon)) <= radiusMeters;
  }

  void _recomputeEstimates() {
    final b = _circleBounds(_camera.target, _radiusMeters);
    int count = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final xMin = _long2tileX(b.southwest.longitude, z);
      final xMax = _long2tileX(b.northeast.longitude, z);
      final yMin = _lat2tileY(b.northeast.latitude, z);
      final yMax = _lat2tileY(b.southwest.latitude, z);
      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          if (_tileCenterInCircle(
            z: z,
            x: x,
            y: y,
            center: _camera.target,
            radiusMeters: _radiusMeters,
          )) count++;
        }
      }
    }
    setState(() {
      _estTiles = count;
      _estMB = (_estTiles * tileSizeBytesGuess) / (1024.0 * 1024.0);
    });
  }

  // ---------- Download ----------
  Future<void> _downloadTiles() async {
    if (_downloading) return;
    if (_mapTilerKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add MAPTILER_KEY to your .env file.')),
      );
      return;
    }

    setState(() => _downloading = true);
    final startedAt = DateTime.now();

    try {
      final b = _circleBounds(_camera.target, _radiusMeters);

      final todo = <({int z, int x, int y})>[];
      for (int z = minZoom; z <= maxZoom; z++) {
        final xMin = _long2tileX(b.southwest.longitude, z);
        final xMax = _long2tileX(b.northeast.longitude, z);
        final yMin = _lat2tileY(b.northeast.latitude, z);
        final yMax = _lat2tileY(b.southwest.latitude, z);
        for (int x = xMin; x <= xMax; x++) {
          for (int y = yMin; y <= yMax; y++) {
            if (_tileCenterInCircle(
              z: z,
              x: x,
              y: y,
              center: _camera.target,
              radiusMeters: _radiusMeters,
            )) {
              todo.add((z: z, x: x, y: y));
            }
          }
        }
      }

      final pack = _OfflinePack(
        id: 'pack_${startedAt.microsecondsSinceEpoch}',
        name:
            'Area @ ${_camera.target.latitude.toStringAsFixed(3)}, ${_camera.target.longitude.toStringAsFixed(3)}',
        center: _camera.target,
        radiusMiles: _radiusMiles,
        minZoom: minZoom,
        maxZoom: maxZoom,
        bytes: 0,
        tiles: todo.length,
        createdAt: startedAt,
        status: OfflinePackStatus.downloading,
      );
      _packs.add(pack);
      await _savePacks();
      setState(() {});

      int done = 0;
      int bytesWritten = 0;
      final queue = List<({int z, int x, int y})>.from(todo);

      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final t = queue.removeLast();
          final outDir = Directory('${_tilesRoot.path}/${pack.id}/${t.z}/${t.x}')
            ..createSync(recursive: true);
          final outFile = File('${outDir.path}/${t.y}.png');

          if (!outFile.existsSync()) {
            try {
              final resp = await _dio.get<List<int>>(
                _tileUrl(t.z, t.x, t.y),
                options: Options(responseType: ResponseType.bytes),
              );
              if (resp.data != null) {
                await outFile.writeAsBytes(resp.data!);
                bytesWritten += resp.data!.length;
              }
            } catch (_) {}
          }
          done++;

          if (mounted && done % 200 == 0) {
            final idx = _packs.indexWhere((p) => p.id == pack.id);
            if (idx != -1) {
              _packs[idx] = _packs[idx].copyWith(
                progress: done / todo.length,
                bytes: bytesWritten,
              );
              await _savePacks();
              setState(() {});
            }
          }
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));

      await _downloadPoisForArea(b, packId: pack.id);

      final idx = _packs.indexWhere((p) => p.id == pack.id);
      if (idx != -1) {
        _packs[idx] = _packs[idx].copyWith(
          progress: 1.0,
          status: OfflinePackStatus.ready,
          bytes: bytesWritten,
          tiles: todo.length,
        );
        await _savePacks();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${todo.length} tiles + POIs')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadPoisForArea(LatLngBounds b,
      {required String packId}) async {
    final south = b.southwest.latitude;
    final west = b.southwest.longitude;
    final north = b.northeast.latitude;
    final east = b.northeast.longitude;

    final query = """
      [out:json][timeout:25];
      (
        node["amenity"="hospital"]($south,$west,$north,$east);
        node["amenity"="police"]($south,$west,$north,$east);
        node["amenity"="fuel"]($south,$west,$north,$east);
        node["shop"="car_repair"]($south,$west,$north,$east);
      );
      out body;
    """;

    try {
      final resp = await _dio.post(
        'https://overpass-api.de/api/interpreter',
        data: {'data': query},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (resp.statusCode == 200) {
        final decoded =
            json.decode(resp.data as String) as Map<String, dynamic>;
        final elements =
            (decoded['elements'] as List).cast<Map<String, dynamic>>();
        final pois = elements.map((e) {
          final tags = (e['tags'] as Map?) ?? {};
          String type = '';
          if (tags['amenity'] == 'hospital') type = 'hospital';
          else if (tags['amenity'] == 'police') type = 'police';
          else if (tags['amenity'] == 'fuel') type = 'gas';
          else if (tags['shop'] == 'car_repair') type = 'mechanic';

          return {
            'id': e['id'],
            'name': (tags['name'] ?? type.toUpperCase()).toString(),
            'type': type,
            'lat': e['lat'],
            'lon': e['lon'],
          };
        }).where((m) => m['type'] != '').toList();

        final outFile = File('${_poisRoot.path}/$packId.json');
        await outFile.writeAsString(json.encode({'pois': pois}));
      }
    } catch (_) {}
  }

  // ---------- Preview ----------
  Future<Tile> _getFileTile(String packId, int x, int y, int z) async {
    final file = File('${_tilesRoot.path}/$packId/$z/$x/$y.png');
    if (!await file.exists()) return TileProvider.noTile;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? TileProvider.noTile : Tile(256, 256, bytes);
  }

  TileOverlay _tileOverlayForPack(_OfflinePack pack) => TileOverlay(
        tileOverlayId: TileOverlayId('offline_${pack.id}'),
        tileProvider: _LocalFileTileProvider(
          (x, y, z) => _getFileTile(
              pack.id, x, y, (z ?? pack.minZoom).clamp(minZoom, maxZoom)),
        ),
        zIndex: 0,
        transparency: 0.0,
      );

  Future<void> _loadPoisForPreview() async {
    _poiMarkers.clear();
    for (final pack in _packs.where((p) => p.status == OfflinePackStatus.ready)) {
      final f = File('${_poisRoot.path}/${pack.id}.json');
      if (!await f.exists()) continue;

      final decoded =
          json.decode(await f.readAsString()) as Map<String, dynamic>;
      final pois = (decoded['pois'] as List).cast<Map<String, dynamic>>();
      for (final p in pois) {
        final type = (p['type'] as String).toLowerCase();
        if (_poiFilter != null && type != _poiFilter) continue;

        final pos =
            LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble());
        final hue = switch (type) {
          'hospital' => BitmapDescriptor.hueRed,
          'police' => BitmapDescriptor.hueBlue,
          'gas' => BitmapDescriptor.hueAzure,
          'mechanic' => BitmapDescriptor.hueOrange,
          _ => BitmapDescriptor.hueRose,
        };
        _poiMarkers.add(
          Marker(
            markerId: MarkerId('${pack.id}_${p['id']}'),
            position: pos,
            infoWindow:
                InfoWindow(title: (p['name'] ?? type).toString()),
            icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          ),
        );
      }
    }
    if (mounted) setState(() {});
  }

  // ---------- My location ----------
  Future<void> _goToMyLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
      }
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
    final target = LatLng(pos.latitude, pos.longitude);
    _camera = CameraPosition(target: target, zoom: _camera.zoom);
    await _map?.animateCamera(CameraUpdate.newLatLng(target));
    _recomputeEstimates();

    if (_saved && _showPois) {
      await _loadPoisForPreview();
    }
  }

  // ---------- Bottom sheet ----------
  void _openPacksSheet() async {
    await _loadPacks();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final downloading = _packs
            .where((p) => p.status == OfflinePackStatus.downloading)
            .toList();
        final ready =
            _packs.where((p) => p.status == OfflinePackStatus.ready).toList();

        if (_packs.isEmpty) {
          return const SizedBox(
            height: 240,
            child: Center(child: Text('No downloaded maps yet.')),
          );
        }

        return SafeArea(
          child: SizedBox(
            height: 440,
            child: ListView(
              children: [
                if (downloading.isNotEmpty)
                  const ListTile(title: Text('Downloading')),
                ...downloading.map((p) => _packTile(p, downloading: true)),
                if (ready.isNotEmpty) const Divider(height: 8),
                if (ready.isNotEmpty)
                  const ListTile(title: Text('Downloaded maps')),
                ...ready.map(_packTile),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _packTile(_OfflinePack p, {bool downloading = false}) {
    final subtitle = downloading
        ? 'Downloading • ${(p.progress * 100).toStringAsFixed(0)}% • ${_fmtBytes(p.bytes)}'
        : '${_fmtMiles(p.radiusMiles)} radius • z${p.minZoom}–${p.maxZoom} • ${_fmtBytes(p.bytes)}';

    return ListTile(
      leading: Icon(downloading ? Icons.downloading : Icons.map),
      title: Text(p.name),
      subtitle: Text(subtitle),
      onTap: downloading
          ? null
          : () async {
              Navigator.pop(context);
              await _map?.animateCamera(CameraUpdate.newLatLngZoom(
                  p.center, p.minZoom.toDouble()));
              setState(() {
                _radiusMiles = p.radiusMiles;
                _camera = CameraPosition(target: p.center, zoom: _camera.zoom);
                _recomputeEstimates();
              });
            },
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'rename') {
            final newName = await _promptRename(p.name);
            if (newName != null && newName.trim().isNotEmpty) {
              final idx = _packs.indexWhere((e) => e.id == p.id);
              if (idx != -1) {
                _packs[idx] = _packs[idx].copyWith(name: newName.trim());
                await _savePacks();
                if (mounted) setState(() {});
              }
            }
          } else if (v == 'delete') {
            try {
              final dir = Directory('${_tilesRoot.path}/${p.id}');
              if (await dir.exists()) await dir.delete(recursive: true);
              final pf = File('${_poisRoot.path}/${p.id}.json');
              if (await pf.exists()) await pf.delete();
            } catch (_) {}
            _packs.removeWhere((e) => e.id == p.id);
            await _savePacks();
            if (mounted) setState(() {});
          } else if (v == 'resize') {
            Navigator.pop(context);
            await _map?.animateCamera(CameraUpdate.newLatLngZoom(
                p.center, p.minZoom.toDouble()));
            setState(() {
              _radiusMiles = p.radiusMiles;
              _recomputeEstimates();
            });
          }
        },
        itemBuilder: (ctx) => [
          if (!downloading)
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
          if (!downloading)
            const PopupMenuItem(
                value: 'resize', child: Text('Update area (re-download)')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Future<String?> _promptRename(String initial) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename map'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Map name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  // ---------- UI ----------
  String _fmtBytes(int b) {
    if (b <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    final i = (math.log(b) / math.log(1024)).floor().clamp(0, units.length - 1);
    return '${(b / math.pow(1024, i)).toStringAsFixed(1)} ${units[i]}';
  }

  String _fmtMiles(double mi) => '${mi.toStringAsFixed(1)} mi';

  Set<Circle> get _selectionCircle => {
        Circle(
          circleId: const CircleId('pick'),
          center: _camera.target,
          radius: _radiusMeters.clamp(500, 80_000),
          strokeWidth: 2,
          strokeColor: Colors.teal,
          fillColor: Colors.teal.withOpacity(0.12),
        ),
      };

  Set<Circle> get _savedPackCircles {
    final out = <Circle>{};
    for (final p in _packs.where((e) => e.status == OfflinePackStatus.ready)) {
      out.add(
        Circle(
          circleId: CircleId('pack_${p.id}'),
          center: p.center,
          radius: (p.radiusMiles * 1609.34).clamp(300.0, 120000.0),
          strokeWidth: 2,
          strokeColor: Colors.green.shade700,
          fillColor: Colors.green.withOpacity(0.08),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final est = _estTiles > 0
        ? '$_estTiles tiles • ~${_estMB.toStringAsFixed(1)} MB (z$minZoom–$maxZoom)'
        : 'Estimating…';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline maps'),
        actions: [
          if (_saved)
            Row(
              children: [
                const Text('POIs'),
                Switch(
                  value: _showPois,
                  onChanged: (v) async {
                    _showPois = v;
                    if (v) {
                      await _loadPoisForPreview();
                    } else {
                      _poiMarkers.clear();
                    }
                    setState(() {});
                  },
                ),
              ],
            ),
          Row(
            children: [
              const Text('Saved'),
              Switch(
                value: _saved,
                onChanged: (v) async {
                  setState(() => _saved = v);
                  _poiFilter = null;
                  if (v && _showPois) {
                    await _loadPoisForPreview();
                  } else {
                    _poiMarkers.clear();
                  }
                  setState(() {});
                },
              ),
            ],
          ),
          IconButton(
            tooltip: 'Downloaded maps',
            onPressed: _openPacksSheet,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: 'Use my location',
            onPressed: _goToMyLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _camera,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            mapType: _saved ? MapType.none : MapType.normal,
            tileOverlays: _saved
                ? {
                    for (final p
                        in _packs.where((e) => e.status == OfflinePackStatus.ready))
                      _tileOverlayForPack(p),
                  }
                : {},
            markers: _saved && _showPois ? _poiMarkers : {},
            circles: _saved ? _savedPackCircles : _selectionCircle,
            onMapCreated: (c) => _map = c,
            onCameraMove: (pos) => _camera = pos,
            onCameraIdle: () async {
              _recomputeEstimates();
              if (_saved && _showPois) {
                await _loadPoisForPreview();
              }
            },
          ),

          if (!_saved)
            Positioned(
              right: 12,
              top: 12,
              child: Card(
                elevation: 2,
                child: SizedBox(
                  width: 56,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Slider(
                      value: _radiusMiles,
                      min: 0.5,
                      max: 50.0,
                      divisions: 99,
                      label: _fmtMiles(_radiusMiles),
                      onChanged: (v) {
                        setState(() => _radiusMiles = v);
                        _recomputeEstimates();
                      },
                    ),
                  ),
                ),
              ),
            ),

          if (!_saved)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(blurRadius: 8, color: Color(0x14000000))
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.download_for_offline_outlined),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Area around map center • $est')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _downloading ? null : _downloadTiles,
                    child: _downloading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Download (tiles + POIs)'),
                  ),
                ],
              ),
            ),

          if (_saved && _showPois)
            Positioned(
              right: 12,
              bottom: 24,
              child: _EmergencyPanel(
                active: _poiFilter,
                onSelect: (value) async {
                  _poiFilter = (value == _poiFilter) ? null : value;
                  await _loadPoisForPreview();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Emergency Panel ----------
class _EmergencyPanel extends StatelessWidget {
  final String? active;
  final ValueChanged<String> onSelect;
  const _EmergencyPanel({required this.active, required this.onSelect});

  Widget _chip(BuildContext ctx,
      {required String key,
      required IconData icon,
      required String label}) {
    final selected = key == active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilterChip(
        selected: selected,
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ]),
        onSelected: (_) => onSelect(key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip(context,
                key: 'mechanic', icon: Icons.build, label: 'Mechanics'),
            _chip(context,
                key: 'hospital',
                icon: Icons.local_hospital,
                label: 'Hospitals'),
            _chip(context,
                key: 'police', icon: Icons.local_police, label: 'Police'),
            _chip(context,
                key: 'gas',
                icon: Icons.local_gas_station,
                label: 'Gas'),
          ],
        ),
      ),
    );
  }
}

// ---------- TileProvider ----------
class _LocalFileTileProvider extends TileProvider {
  final Future<Tile> Function(int x, int y, int? z) _loader;
  _LocalFileTileProvider(this._loader);
  @override
  Future<Tile> getTile(int x, int y, int? zoom) => _loader(x, y, zoom);
}

// ---------- Pack model ----------
enum OfflinePackStatus { downloading, ready }

class _OfflinePack {
  final String id;
  final String name;
  final LatLng center;
  final double radiusMiles;
  final int minZoom;
  final int maxZoom;
  final int bytes;
  final int tiles;
  final DateTime createdAt;
  final OfflinePackStatus status;
  final double progress;

  _OfflinePack({
    required this.id,
    required this.name,
    required this.center,
    required this.radiusMiles,
    required this.minZoom,
    required this.maxZoom,
    required this.bytes,
    required this.tiles,
    required this.createdAt,
    required this.status,
    this.progress = 0.0,
  });

  _OfflinePack copyWith({
    String? id,
    String? name,
    LatLng? center,
    double? radiusMiles,
    int? minZoom,
    int? maxZoom,
    int? bytes,
    int? tiles,
    DateTime? createdAt,
    OfflinePackStatus? status,
    double? progress,
  }) {
    return _OfflinePack(
      id: id ?? this.id,
      name: name ?? this.name,
      center: center ?? this.center,
      radiusMiles: radiusMiles ?? this.radiusMiles,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      bytes: bytes ?? this.bytes,
      tiles: tiles ?? this.tiles,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'center': {'lat': center.latitude, 'lng': center.longitude},
        'radiusMiles': radiusMiles,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'bytes': bytes,
        'tiles': tiles,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'progress': progress,
      };

  factory _OfflinePack.fromJson(Map<String, dynamic> m) => _OfflinePack(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Offline area',
        center: LatLng(
          (m['center']?['lat'] as num?)?.toDouble() ?? 0,
          (m['center']?['lng'] as num?)?.toDouble() ?? 0,
        ),
        radiusMiles: (m['radiusMiles'] as num?)?.toDouble() ?? 5.0,
        minZoom: (m['minZoom'] as num?)?.toInt() ?? _OfflineMapsPageState.minZoom,
        maxZoom: (m['maxZoom'] as num?)?.toInt() ?? _OfflineMapsPageState.maxZoom,
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
        tiles: (m['tiles'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        status: ((m['status'] as String?) == 'ready')
            ? OfflinePackStatus.ready
            : OfflinePackStatus.downloading,
        progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
      );
}
