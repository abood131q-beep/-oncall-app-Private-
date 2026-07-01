import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'session_service.dart';

// ===== عنوان السيرفر (نفس config.dart) =====
const String _serverUrl = 'http://localhost:3000';
// للهاتف الحقيقي: 'http://192.168.X.X:3000'

// ===== نموذج المكان =====
class PlaceResult {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;

  PlaceResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });
}

// ===== بحث عبر السيرفر (يتجنب CORS) =====
Future<List<Map<String, dynamic>>> searchPlaces(String query, {
  double? lat,
  double? lng,
}) async {
  if (query.trim().isEmpty) return [];

  try {
    String url = '$_serverUrl/places/autocomplete?input=${Uri.encodeComponent(query)}';
    if (lat != null && lng != null) {
      url += '&lat=$lat&lng=$lng';
    }

    final response = await http.get(Uri.parse(url))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK') {
        return List<Map<String, dynamic>>.from(data['predictions']);
      }
    }
  } catch (e) {
    debugPrint('Places search error: $e');
  }
  return [];
}

// ===== جلب تفاصيل المكان عبر السيرفر =====
Future<PlaceResult?> getPlaceDetails(String placeId) async {
  try {
    final url = '$_serverUrl/places/details?place_id=$placeId';

    final response = await http.get(Uri.parse(url))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK') {
        final result = data['result'];
        return PlaceResult(
          placeId: placeId,
          name: result['name'] ?? '',
          address: result['formatted_address'] ?? '',
          lat: result['geometry']['location']['lat'].toDouble(),
          lng: result['geometry']['location']['lng'].toDouble(),
        );
      }
    }
  } catch (e) {
    debugPrint('Place details error: $e');
  }
  return null;
}

// ===== Widget البحث عن مكان =====
class PlacesSearchField extends StatefulWidget {
  final String hint;
  final IconData prefixIcon;
  final Color iconColor;
  final Function(PlaceResult) onPlaceSelected;
  final TextEditingController controller;
  final double? biasLat;
  final double? biasLng;

  const PlacesSearchField({
    super.key,
    required this.hint,
    required this.prefixIcon,
    required this.iconColor,
    required this.onPlaceSelected,
    required this.controller,
    this.biasLat,
    this.biasLng,
  });

  @override
  State<PlacesSearchField> createState() => _PlacesSearchFieldState();
}

class _PlacesSearchFieldState extends State<PlacesSearchField> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce; // ✅ Debounce

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    // ✅ إلغاء الطلب السابق
    _debounce?.cancel();

    if (value.length < 2) {
      setState(() { _suggestions = []; _showSuggestions = false; _isLoading = false; });
      return;
    }

    setState(() => _isLoading = true);

    // ✅ انتظر 500ms قبل الإرسال
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await searchPlaces(
        value,
        lat: widget.biasLat,
        lng: widget.biasLng,
      );

      if (mounted) {
        setState(() {
          _suggestions = results;
          _showSuggestions = results.isNotEmpty;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _onSelect(Map<String, dynamic> prediction) async {
    final description = prediction['description'] ?? '';
    widget.controller.text = description;

    setState(() { _showSuggestions = false; _isLoading = true; });
    _focusNode.unfocus();

    final placeId = prediction['place_id'] ?? '';
    if (placeId.isNotEmpty) {
      final details = await getPlaceDetails(placeId);
      if (details != null && mounted) {
        widget.onPlaceSelected(details);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.hint,
            prefixIcon: Icon(widget.prefixIcon, color: widget.iconColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() { _suggestions = []; _showSuggestions = false; });
                        },
                      )
                    : null,
          ),
        ),

        // قائمة الاقتراحات
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
            ),
            child: Material(
              color: Colors.transparent,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _suggestions.length > 5 ? 5 : _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final place = _suggestions[i];
                  final mainText = place['structured_formatting']?['main_text'] ?? place['description'] ?? '';
                  final secondaryText = place['structured_formatting']?['secondary_text'] ?? '';

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on, color: Colors.indigo, size: 20),
                    title: Text(mainText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: secondaryText.isNotEmpty
                        ? Text(secondaryText, style: const TextStyle(fontSize: 12, color: Colors.grey))
                        : null,
                    onTap: () => _onSelect(place),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
