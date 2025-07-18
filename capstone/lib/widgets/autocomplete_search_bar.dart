import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/places_service.dart';
import 'package:uuid/uuid.dart';
import '../utils/debouncer.dart';

class AutocompleteSearchBar extends StatefulWidget {
  // A callback function passed when using the AutocompleteSearchBar
  // widget, to do something after a suggestion is tapped/selected.
  final Function(LatLng) onSuggestionSelected;  const AutocompleteSearchBar({
    super.key,
    required this.onSuggestionSelected,
  });  @override
  State<AutocompleteSearchBar> createState() => _AutocompleteSearchBarState();
}class _AutocompleteSearchBarState extends State<AutocompleteSearchBar> {
  String? _currentQuery;
  late Iterable<Widget> _lastOptions = <Widget>[];
  late final Debounceable<List<Suggestion>?, String> _debouncedSearch;
  PlaceApiProvider? _placeApi;
  String? _sessionToken;  @override
  void initState() {
    super.initState();
    // Debounce the _search function using our code from debouncer.dart
    _debouncedSearch = debounce<List<Suggestion>?, String>(_search);
  }  @override
  void dispose() {
    _sessionToken = null;
    _placeApi = null;
    super.dispose();
  }  Future<List<Suggestion>?> _search(String query) async {
    _currentQuery = query;    if (_placeApi == null) {
      debugPrint('Place API provider not initialized.');
      return null;
    }    // In a real application, there should be some error handling here.
    final List<Suggestion> options = await _placeApi!.fetchSuggestions(
        _currentQuery!, Localizations.localeOf(context).languageCode);    if (_currentQuery != query) {
      return null;
    }
    _currentQuery = null;    return options;
  }  void _startSearchSession() {
    _sessionToken = const Uuid().v4();
    _placeApi = PlaceApiProvider(_sessionToken);
  }  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;    return Container(
      padding: const EdgeInsets.all(10.0),
      child: SearchAnchor(
        isFullScreen: false,
        viewConstraints: BoxConstraints(
          // Set the height of the suggestions box
          maxHeight: screenHeight * 0.3,
        ),
        builder: (BuildContext context, SearchController controller) {
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(
                    Icons.search,
                    size: 15.0,
                  ),
                  label: const Text("Search a location"),
                  onPressed: () {
                    _startSearchSession();
                    controller.openView();
                  },
                ),
              ),
            ),
          ]);
        },
        suggestionsBuilder:
            (BuildContext context, SearchController controller) async {
          _currentQuery = controller.text;
          final List<Suggestion>? options =
              (await _debouncedSearch(controller.text))?.toList();
          if (options == null) {
            return _lastOptions;
          }          _lastOptions = List<ListTile>.generate(options.length, (int index) {
            final Suggestion item = options[index];
            return ListTile(
                title: Text(item.description),
                onTap: () async {
                  LatLng latLng =
                      await _placeApi!.getPlaceCoordinatesFromId(item.placeId);
                  // Call our function when a suggestion is tapped
                  widget.onSuggestionSelected(latLng);
                  controller.closeView(null);
                });
          });          return _lastOptions;
        },
      ),
    );
  }
}