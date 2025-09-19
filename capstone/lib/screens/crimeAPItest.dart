import 'dart:io';
import 'package:flutter/material.dart';
import '../services/crimeometer_service.dart';


// Screen for testing Crimeometer API responses by manually inputting values
class CrimeTestScreen extends StatefulWidget {
  const CrimeTestScreen({super.key});

  @override
  State<CrimeTestScreen> createState() => _CrimeTestScreenState();
}

//Crime screen state
class _CrimeTestScreenState extends State<CrimeTestScreen> {

  // Values input into crimeometer call
  final _latCtl = TextEditingController(text: '40.7128');    // Default New York City
  final _lonCtl = TextEditingController(text: '-74.0060');
  final _distCtl = TextEditingController(text: '1.0');       // distance, in miles
  final _daysCtl = TextEditingController(text: '30');        // timeframe in days, default 30 (values under 7 and 14 tend to not be available)
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;

  // Crimeometer Service instance
  final _service = CrimeometerService();
  Future<void> _fetchAndShow() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true; // set state to loading on a call
      _error = null;
    });

    // 
    try {

      //parse values into Crimeometer service's format
      final lat = double.parse(_latCtl.text.trim());
      final lon = double.parse(_lonCtl.text.trim());
      final dist = double.parse(_distCtl.text.trim());
      final days = int.parse(_daysCtl.text.trim());

      // feed values into fetchCrimeData method
      final data = await _service.fetchCrimeData(
        latitude: lat,
        longitude: lon,
        distanceMiles: dist,
        daysAgo: days,
        page: 1,          // default 1 page is 1 API call
        pageSize: null,   // test later, default null in testing page, try "max"
      );

      // call Incident parsing method (below)
      final incidents = _coerceIncidentList(data);

      // finish if successful
      if (!mounted) return;

      // for empty results, display a snackbar 
      if (incidents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No incidents found for that query.')),
        );
        setState(() => _loading = false); // cancel loading state
        return;
      }

      setState(() => _loading = false); //cancel loading state after success
      _showCrimesSheet(context, incidents); // call crime sheet display function
    } on SocketException catch (e) {
      setState(() {
        _loading = false;
        _error = 'Network error: ${e.message}'; // display an error if there is an issue 
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  // Parses the API response into seperate 'incidents' as a list
  List<dynamic> _coerceIncidentList(Map<String, dynamic> payload) {
    // Direct list under "incidents"
    final i1 = payload['incidents'];
    if (i1 is List) return i1;

    // Some responses put them under "data"
    final i2 = payload['data'];
    if (i2 is List) return i2;

    // Some wrap with paging: { data: { incidents: [...] } } or { results: [...] }
    final dataObj = payload['data'];
    if (dataObj is Map && dataObj['incidents'] is List) {
      return (dataObj['incidents'] as List);
    }
    if (payload['results'] is List) return (payload['results'] as List);

    // Fallback: nothing recognized
    return const [];
  }


  // Display crime results on a scrollable sheet, like it will be with searches.
  // Most below UI Assisted by ChatGPT, insists on multiple variants of field names, can definitely clean up after analyzing json outputs
  void _showCrimesSheet(BuildContext context, List<dynamic> incidents) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (_, scrollCtl) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Crimes (first page)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtl,
                    itemCount: incidents.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = incidents[i] as Map<String, dynamic>? ?? {};
                      // Try common field names (Crimeometer/RapidAPI variants vary)
                      final offense = _firstNonEmpty(item, [
                        'incident_offense',
                        'incident_type',
                        'offense',
                        'ucr_offense',
                        'nibrs_code',
                      ]);
                      final when = _firstNonEmpty(item, [
                        'incident_date',
                        'incident_datetime',
                        'reported_at',
                        'date',
                        'datetime',
                      ]);
                      final addr = _firstNonEmpty(item, [
                        'incident_address',
                        'address',
                        'formatted_address',
                        'block_address',
                      ]);
                      final dist = _firstNonEmpty(item, ['distance', 'dist']);
                      final src = _firstNonEmpty(item, ['incident_offense_description', 'description', 'summary']);

                      return ListTile(
                        dense: true,
                        title: Text(
                          offense?.toString() ?? 'Unknown offense',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (when != null) Text(when.toString()),
                            if (addr != null) Text(addr.toString()),
                            if (src != null) Text(src.toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                        trailing: (dist != null) ? Text(dist.toString()) : null,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }


  String? _firstNonEmpty(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      return v.toString();
    }
    return null;
  }

  String? _v(String s) => s.trim().isEmpty ? null : s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Crimeometer Test')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Latitude'),
                        validator: (s) {
                          final v = _v(s ?? '');
                          if (v == null) return 'Required';
                          final d = double.tryParse(v);
                          if (d == null || d < -90 || d > 90) return 'Invalid latitude';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lonCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Longitude'),
                        validator: (s) {
                          final v = _v(s ?? '');
                          if (v == null) return 'Required';
                          final d = double.tryParse(v);
                          if (d == null || d < -180 || d > 180) return 'Invalid longitude';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _distCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Distance (mi)'),
                        validator: (s) {
                          final v = _v(s ?? '');
                          if (v == null) return 'Required';
                          final d = double.tryParse(v);
                          if (d == null || d <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _daysCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Days ago'),
                        validator: (s) {
                          final v = _v(s ?? '');
                          if (v == null) return 'Required';
                          final d = int.tryParse(v);
                          if (d == null || d <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loading ? null : _fetchAndShow,
                  icon: _loading
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: const Text('Fetch crimes & show modal'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Note: This screen makes a single API call (page=1) and shows what comes back.\n'
                  'Once we confirm the shape for your key/plan, we can wire up paging & filters.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
