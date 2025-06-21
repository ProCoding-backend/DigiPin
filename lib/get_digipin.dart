import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:digipin/digipin.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_maps_webservice/places.dart';
import 'digipin_entry.dart';
import 'digipin_storage.dart';

const String googleApiKey =
    'YOUR_API_KEY'; // <-- Replace with your API key

class GetDigipinPage extends StatefulWidget {
  @override
  State<GetDigipinPage> createState() => _GetDigipinPageState();
}

class _GetDigipinPageState extends State<GetDigipinPage> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _selectedPosition;
  bool _showResult = false;
  String? _digiPin;
  final TextEditingController _searchController = TextEditingController();
  final GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: googleApiKey);

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _selectedPosition = LatLng(position.latitude, position.longitude);
    });
  }

  void _onCameraMove(CameraPosition position) {
    if (!_showResult) {
      setState(() {
        _selectedPosition = position.target;
      });
    }
  }

  void _onGetDigipinPressed() async {
    if (_selectedPosition != null) {
      try {
        final pin = DigiPin.getDigiPin(
          _selectedPosition!.latitude,
          _selectedPosition!.longitude,
        );
        setState(() {
          _digiPin = pin;
          _showResult = true;
        });
        // Save to local storage
        await DigipinStorage.add(
          DigipinEntry(
            digipin: pin,
            latitude: _selectedPosition!.latitude,
            longitude: _selectedPosition!.longitude,
          ),
        );
      } catch (e) {
        setState(() {
          _digiPin = "Error generating DigiPin";
          _showResult = true;
        });
      }
    }
  }

  void _onGetNewDigipinPressed() {
    setState(() {
      _showResult = false;
      _digiPin = null;
    });
  }

  void _copyDigipin() {
    if (_digiPin != null && _digiPin != "DIGIPIN") {
      Clipboard.setData(ClipboardData(text: _digiPin!));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('DIGIPIN copied to clipboard')));
    }
  }

  Future<List<Prediction>> _searchPlaces(String query) async {
    if (query.isEmpty) return [];
    final response = await _places.autocomplete(query, language: "en");
    if (response.isOkay) {
      return response.predictions;
    }
    return [];
  }

  Future<void> _moveToPlace(Prediction prediction) async {
    final detail = await _places.getDetailsByPlaceId(prediction.placeId!);
    if (detail.isOkay) {
      final location = detail.result.geometry!.location;
      final latLng = LatLng(location.lat, location.lng);
      _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
      setState(() {
        _selectedPosition = latLng;
        _searchController.text =
            detail.result.name ?? prediction.description ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double compactHeight = 70;
    final double expandedHeight = MediaQuery.of(context).size.height * 0.32;

    return Scaffold(
      appBar: AppBar(
        title: Text('Get DIGIPIN'),
        backgroundColor: Color(0xFF00B2FF),
      ),
      body: _currentPosition == null
          ? Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition!,
                    zoom: 16,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  onMapCreated: (controller) => _mapController = controller,
                  onCameraMove: _onCameraMove,
                  onCameraIdle: () {
                    if (!_showResult && _mapController != null) {
                      _mapController!.getVisibleRegion().then((bounds) async {
                        LatLng center = await _mapController!.getLatLng(
                          ScreenCoordinate(
                            x: (MediaQuery.of(context).size.width ~/ 2),
                            y: (MediaQuery.of(context).size.height ~/ 2),
                          ),
                        );
                        setState(() {
                          _selectedPosition = center;
                        });
                      });
                    }
                  },
                ),
                // Search bar at the top
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TypeAheadField(
                      controller: _searchController,
                      suggestionsCallback: _searchPlaces,
                      itemBuilder: (context, Prediction suggestion) {
                        return ListTile(
                          title: Text(suggestion.description ?? ''),
                        );
                      },
                      onSelected: (suggestion) {
                        _moveToPlace(suggestion as Prediction);
                      },
                      emptyBuilder: (context) => Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('No places found'),
                      ),
                      builder: (context, controller, focusNode) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            hintText:
                                'Search place, area, address or coordinates',
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 20,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Center pointer
                IgnorePointer(
                  child: Center(
                    child: Icon(
                      Icons.location_on,
                      size: 48,
                      color: Color(0xFF00B2FF),
                    ),
                  ),
                ),
                // Bottom animated container inside SafeArea
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: _showResult ? expandedHeight : compactHeight,
                      margin: EdgeInsets.only(left: 24, right: 24, bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      child: _showResult
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _digiPin ?? "DIGIPIN",
                                  style: TextStyle(
                                    color: Colors.deepPurple,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  _selectedPosition != null
                                      ? '${_selectedPosition!.latitude.toStringAsFixed(8)}, ${_selectedPosition!.longitude.toStringAsFixed(8)}'
                                      : 'No location selected',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _copyDigipin,
                                      icon: Icon(
                                        Icons.copy,
                                        color: Colors.white,
                                      ),
                                      label: Text(
                                        'Copy',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Color(0xFF00B2FF),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Spacer(),
                                Center(
                                  child: ElevatedButton(
                                    onPressed: _onGetNewDigipinPressed,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xFF00B2FF),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                    child: Text(
                                      'Get DIGIPIN of New Place',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Select a location to get DIGIPIN',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: _onGetDigipinPressed,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF00B2FF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  child: Text(
                                    'Get DIGIPIN',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
