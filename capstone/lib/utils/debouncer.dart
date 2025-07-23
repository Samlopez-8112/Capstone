import 'dart:async';

// assisted by https://levelup.gitconnected.com/flutter-google-maps-autocomplete-searchbar-with-debouncing-f5a215ee7381

// Debouncer reduces the calls to Google Places API while still allowing for autocompleted searches
typedef Debounceable<S, T> = Future<S?> Function(T parameter);
// Adjust the delay here
const Duration debounceDuration = Duration(milliseconds: 350); // wait 350 seconds to make a call

Debounceable<S, T> debounce<S, T>(Debounceable<S?, T> function) { // if timer drops below 350, run, if user input occurs, reset timer.
  _DebounceTimer? debounceTimer;

  return (T parameter) async {
    if (debounceTimer != null && !debounceTimer!.isCompleted) {
      debounceTimer!.cancel();
    }
    debounceTimer = _DebounceTimer();
    try {
      await debounceTimer!.future;
    } catch (error) {
      if (error is _CancelException) {
        return null;
      }
      rethrow;
    }
    return function(parameter);
  };
}

class _DebounceTimer {
  _DebounceTimer() {
    _timer = Timer(debounceDuration, _onComplete);
  }

  late final Timer _timer;
  final Completer<void> _completer = Completer<void>();

  void _onComplete() {
    _completer.complete();
  }

  Future<void> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  void cancel() {
    _timer.cancel();
    _completer.completeError(const _CancelException());
  }
}

class _CancelException implements Exception {
  const _CancelException();
}