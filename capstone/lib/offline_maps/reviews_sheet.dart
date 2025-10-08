// lib/offline_maps/reviews_sheet.dart
import 'package:flutter/material.dart';
import 'offline_reviews.dart';

class ReviewsSheet extends StatefulWidget {
  final String poiId;
  final OfflineReviews reviews;

  // Optional details to show at the top (if we have them from OSM/Places)
  final String? name;
  final String? address;
  final String? phone;
  final String? website;
  final double? avgRating;

  const ReviewsSheet({
    super.key,
    required this.poiId,
    required this.reviews,
    this.name,
    this.address,
    this.phone,
    this.website,
    this.avgRating,
  });

  @override
  State<ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<ReviewsSheet> {
  late Future<List<Map<String, dynamic>>> _reviewsFuture;
  int? _selectedRating;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reviewsFuture = widget.reviews.getReviews(widget.poiId);
  }

  Future<void> _submitReview() async {
    if (_selectedRating == null || _commentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a rating and comment')),
      );
      return;
    }

    final review = {
      'rating': _selectedRating!,
      'comment': _commentCtrl.text.trim(),
      'date': DateTime.now().toIso8601String(),
    };

    setState(() {
      _reviewsFuture = widget.reviews.getReviews(widget.poiId);
      _selectedRating = null;
      _commentCtrl.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your review was saved')),
      );
    }
  }

  Widget _starsStatic(double value) {
    final full = value.floor();
    final hasHalf = (value - full) >= 0.5;
    return Row(
      children: [
        ...List.generate(5, (i) {
          if (i < full) {
            return const Icon(Icons.star, color: Colors.amber, size: 18);
          } else if (i == full && hasHalf) {
            return const Icon(Icons.star_half, color: Colors.amber, size: 18);
          }
          return const Icon(Icons.star_border, color: Colors.amber, size: 18);
        }),
      ],
    );
  }

  Widget _starsPicker(int current, void Function(int) onPick) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = i < current;
        return IconButton(
          icon: Icon(
            filled ? Icons.star : Icons.star_border,
            color: filled ? Colors.amber : Colors.grey,
            size: 30,
          ),
          onPressed: () => onPick(i + 1),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _reviewsFuture,
          builder: (context, snap) {
            final reviews = snap.data ?? [];
            final avg = widget.avgRating ??
                (reviews.isEmpty
                    ? 0
                    : reviews.fold<int>(0, (a, r) => a + (r['rating'] as int)) /
                        reviews.length);

            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Color(0x22000000))],
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),

                    // Header (name + rating)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            widget.name ?? 'Unknown place',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        _starsStatic(avg),
                        const SizedBox(width: 6),
                        Text(avg.toStringAsFixed(1)),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Redesigned info rows
                    if (widget.address?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.address!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.phone?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.phone!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.website?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.public, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.website!,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: Colors.blue[700]),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),
                    Divider(color: Colors.grey.shade300),

                    // Reviews list
                    if (reviews.isNotEmpty)
                      ...reviews.map((r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < (r['rating'] as int)
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                ),
                              ),
                              subtitle: Text(r['comment'] ?? ''),
                              trailing: Text(
                                (r['date'] as String)
                                    .split('T')
                                    .first
                                    .replaceAll('-', '/'),
                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                              ),
                            ),
                          )),
                    if (reviews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: Text('No reviews yet. Be the first!')),
                      ),

                    const SizedBox(height: 10),
                    Divider(color: Colors.grey.shade300),

                    // "Rate this place"
                    const SizedBox(height: 6),
                    Center(
                      child: Text('Your rating',
                          style: theme.textTheme.titleMedium),
                    ),
                    const SizedBox(height: 6),
                    _starsPicker(_selectedRating ?? 0,
                        (v) => setState(() => _selectedRating = v)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _commentCtrl,
                      minLines: 2,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Write a short comment…',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitReview,
                        style: ElevatedButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Rate this place'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
