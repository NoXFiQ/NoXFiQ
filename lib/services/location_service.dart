import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

class LocationService extends ChangeNotifier {
  final loc.Location _location = loc.Location();
  
  Position? _currentPosition;
  LocationData? _selectedLocation;
  bool _isLoading = false;
  String _selectedRegion = '';
  String _selectedDistrict = '';
  
  Position? get currentPosition => _currentPosition;
  LocationData? get selectedLocation => _selectedLocation;
  bool get isLoading => _isLoading;
  String get selectedRegion => _selectedRegion;
  String get selectedDistrict => _selectedDistrict;
  
  // Initialize location service
  Future<void> initialize() async {
    await _checkPermissions();
    await getCurrentLocation();
  }
  
  // Check location permissions
  Future<bool> _checkPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;
    
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }
    
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return true;
  }
  
  // Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final hasPermission = await _checkPermissions();
      if (!hasPermission) {
        return null;
      }
      
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      if (_currentPosition != null) {
        await _updateLocationFromCoordinates(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      }
      
      return _currentPosition;
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Update location from coordinates
  Future<void> _updateLocationFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        
        // Try to map to Tanzania regions
        final region = _mapToTanzaniaRegion(placemark.administrativeArea ?? '');
        final district = _mapToTanzaniaDistrict(placemark.locality ?? '');
        
        _selectedLocation = LocationData(
          latitude: lat,
          longitude: lng,
          region: region,
          district: district,
          ward: placemark.subLocality ?? '',
          street: placemark.thoroughfare ?? '',
          address: '${placemark.thoroughfare ?? ''}, ${placemark.locality ?? ''}',
        );
        
        _selectedRegion = region;
        _selectedDistrict = district;
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating location from coordinates: $e');
    }
  }
  
  // Set location manually
  Future<void> setLocation({
    required String region,
    required String district,
    required String ward,
    required String street,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Try to get coordinates for the address
      final address = '$street, $ward, $district, $region, Tanzania';
      final locations = await locationFromAddress(address);
      
      if (locations.isNotEmpty) {
        final location = locations.first;
        _selectedLocation = LocationData(
          latitude: location.latitude,
          longitude: location.longitude,
          region: region,
          district: district,
          ward: ward,
          street: street,
          address: address,
        );
      } else {
        // If geocoding fails, use center of Tanzania as fallback
        _selectedLocation = LocationData(
          latitude: -6.369028,
          longitude: 34.888822,
          region: region,
          district: district,
          ward: ward,
          street: street,
          address: '$street, $ward, $district, $region',
        );
      }
      
      _selectedRegion = region;
      _selectedDistrict = district;
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting location: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Get location from map selection
  Future<void> setLocationFromMap(LatLng position) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      await _updateLocationFromCoordinates(
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      debugPrint('Error setting location from map: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Calculate distance between two locations
  double calculateDistance(LocationData location1, LocationData location2) {
    return Geolocator.distanceBetween(
      location1.latitude,
      location1.longitude,
      location2.latitude,
      location2.longitude,
    );
  }
  
  // Get formatted distance
  String getFormattedDistance(LocationData location1, LocationData location2) {
    final distance = calculateDistance(location1, location2);
    
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }
  
  // Check if location is within Tanzania
  bool isLocationInTanzania(double lat, double lng) {
    // Tanzania approximate boundaries
    const minLat = -11.745;
    const maxLat = -0.990;
    const minLng = 29.327;
    const maxLng = 40.443;
    
    return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
  }
  
  // Map administrative area to Tanzania region
  String _mapToTanzaniaRegion(String administrativeArea) {
    final regions = TanzaniaRegions.allRegions;
    
    for (final region in regions) {
      if (administrativeArea.toLowerCase().contains(region.toLowerCase())) {
        return region;
      }
    }
    
    // Default to Dar es Salaam if not found
    return 'Dar es Salaam';
  }
  
  // Map locality to Tanzania district
  String _mapToTanzaniaDistrict(String locality) {
    for (final region in TanzaniaRegions.regions.entries) {
      for (final district in region.value) {
        if (locality.toLowerCase().contains(district.toLowerCase())) {
          return district;
        }
      }
    }
    
    // Default to Ilala if not found
    return 'Ilala';
  }
  
  // Get districts for a region
  List<String> getDistrictsForRegion(String region) {
    return TanzaniaRegions.getDistricts(region);
  }
  
  // Get all regions
  List<String> getAllRegions() {
    return TanzaniaRegions.allRegions;
  }
  
  // Search locations
  Future<List<LocationData>> searchLocations(String query) async {
    try {
      final locations = await locationFromAddress('$query, Tanzania');
      final List<LocationData> results = [];
      
      for (final location in locations) {
        if (isLocationInTanzania(location.latitude, location.longitude)) {
          final placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );
          
          if (placemarks.isNotEmpty) {
            final placemark = placemarks.first;
            results.add(LocationData(
              latitude: location.latitude,
              longitude: location.longitude,
              region: _mapToTanzaniaRegion(placemark.administrativeArea ?? ''),
              district: _mapToTanzaniaDistrict(placemark.locality ?? ''),
              ward: placemark.subLocality ?? '',
              street: placemark.thoroughfare ?? '',
              address: '${placemark.thoroughfare ?? ''}, ${placemark.locality ?? ''}',
            ));
          }
        }
      }
      
      return results;
    } catch (e) {
      debugPrint('Error searching locations: $e');
      return [];
    }
  }
  
  // Get nearby locations
  Future<List<LocationData>> getNearbyLocations(LocationData center, double radiusKm) async {
    try {
      // This would typically query a database of locations
      // For now, return empty list as it depends on your backend
      return [];
    } catch (e) {
      debugPrint('Error getting nearby locations: $e');
      return [];
    }
  }
  
  // Validate location
  bool validateLocation(LocationData location) {
    if (location.region.isEmpty || location.district.isEmpty) {
      return false;
    }
    
    if (!isLocationInTanzania(location.latitude, location.longitude)) {
      return false;
    }
    
    return true;
  }
  
  // Get location suggestions based on partial input
  List<String> getLocationSuggestions(String input) {
    final suggestions = <String>[];
    
    if (input.isEmpty) return suggestions;
    
    // Search in regions
    for (final region in TanzaniaRegions.allRegions) {
      if (region.toLowerCase().contains(input.toLowerCase())) {
        suggestions.add(region);
      }
    }
    
    // Search in districts
    for (final regionEntry in TanzaniaRegions.regions.entries) {
      for (final district in regionEntry.value) {
        if (district.toLowerCase().contains(input.toLowerCase())) {
          suggestions.add('$district, ${regionEntry.key}');
        }
      }
    }
    
    return suggestions.take(10).toList();
  }
  
  // Get center of Tanzania (fallback location)
  LocationData getTanzaniaCenter() {
    return LocationData(
      latitude: -6.369028,
      longitude: 34.888822,
      region: 'Dodoma',
      district: 'Dodoma Urban',
      ward: 'Central',
      street: 'Central Street',
      address: 'Central Street, Dodoma Urban, Dodoma',
    );
  }
  
  // Clear selected location
  void clearSelectedLocation() {
    _selectedLocation = null;
    _selectedRegion = '';
    _selectedDistrict = '';
    notifyListeners();
  }
  
  // Update selected region
  void updateSelectedRegion(String region) {
    _selectedRegion = region;
    _selectedDistrict = '';
    notifyListeners();
  }
  
  // Update selected district
  void updateSelectedDistrict(String district) {
    _selectedDistrict = district;
    notifyListeners();
  }
}