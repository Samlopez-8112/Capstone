import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/places_service.dart';
import 'package:uuid/uuid.dart';
import '../utils/debouncer.dart';

//Search bar widget displays location suggestions from Google Places API
//returns coordinates of selected location.
class AutocompleteSearchBar extends StatefulWidget {
  // onSuggestionSelected is a callback function used to do something
  // after a suggestion is tapped
  final Function(LatLng) onSuggestionSelected;  const AutocompleteSearchBar({
    super.key,
    required this.onSuggestionSelected,
  });  @override
  State<AutocompleteSearchBar> createState() => _AutocompleteSearchBarState();
}

class _AutocompleteSearchBarState extends State<AutocompleteSearchBar> {
  String? _currentQuery;

  // Stores last generated suggestions
  late Iterable<Widget> _lastOptions = <Widget>[];
  // use debounced search to reduce api calls
  late final Debounceable<List<Suggestion>?, String> _debouncedSearch;
  PlaceApiProvider? _placeApi; // Places API provider

  String? _sessionToken; // each autocompleting session has a unique token  
  
  @override
  void initState() {
    super.initState();
    // initialize debouncer to delay '_search' method calls
    _debouncedSearch = debounce<List<Suggestion>?, String>(_search);
  }
  
    @override
  // save resources by disposing
  void dispose() {
    _sessionToken = null;
    _placeApi = null;
    super.dispose();
  }
  
    // Grabs suggestions from Places API based on input
    Future<List<Suggestion>?> _search(String query) async {
    _currentQuery = query;    if (_placeApi == null) {
      debugPrint('Place API provider not initialized.');
      return null;
    }
    
    // use user's 'locale' for more logical suggestions 
    final List<Suggestion> options = await _placeApi!.fetchSuggestions(
        _currentQuery!, Localizations.localeOf(context).languageCode);    
        if (_currentQuery != query) { // ensure we're returning the current result
      return null;
    }
    _currentQuery = null;    
    return options;
  }
  
  // Starts the session for Google Places
    void _startSearchSession() {
    _sessionToken = const Uuid().v4();
    _placeApi = PlaceApiProvider();
  } 
  
   @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;    return Container(
      padding: const EdgeInsets.all(10.0),
      child: SearchAnchor(
        isFullScreen: false,
        viewConstraints: BoxConstraints(
          // Set the height of the suggestions box
          maxHeight: screenHeight * 0.3,
        ),
        // Search bar UI
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
         // generate list of suggestions
        suggestionsBuilder:
            (BuildContext context, SearchController controller) async {
          _currentQuery = controller.text;
          // fetch the suggestions
          final List<Suggestion>? options =
              (await _debouncedSearch(controller.text))?.toList();
          if (options == null) {
            return _lastOptions;
          }

          // Place each suggestion in a clickable 'ListTile' 
          _lastOptions = List<ListTile>.generate(options.length, (int index) {
            final Suggestion item = options[index];
            return ListTile(
                title: Text(item.description),
                onTap: () async {
                  LatLng latLng =
                      await _placeApi!.getPlaceCoordinatesFromId(item.placeId);
                  // Call our function when a suggestion is tapped
                  widget.onSuggestionSelected(latLng);
                  controller.closeView(null); //Close suggestions bar when one is tapped
                });
          });          return _lastOptions;
        },
      ),
    );
  }
}