import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data'; // Added import for ByteData
import 'package:flutter/services.dart' show rootBundle; // Added for asset loading
import 'dart:math'; // Added for min function

void main() {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KMZ Map Viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  bool _isLoading = false;
  GoogleMapController? _mapController;
  Set<Polygon> _polygons = {};
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  bool _permissionsGranted = false;
  
  // Default camera position (can be changed to your desired location)
  final CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    // Request permissions when the app starts
    _requestPermissions();
    
    // Load bundled KMZ regardless of permissions (we'll check inside the method)
    Future.delayed(const Duration(seconds: 1), () {
      _loadBundledKMZ();
    });
  }

  Future<void> _requestPermissions() async {
    try {
      // Request multiple permissions at once
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.storage,  // For file access
        Permission.camera,   // For picking media
      ].request();
      
      bool allGranted = true;
      statuses.forEach((permission, status) {
        if (!status.isGranted) {
          allGranted = false;
        }
      });
      
      setState(() {
        _permissionsGranted = allGranted;
      });
      
      if (allGranted) {
        // Try to load bundled KMZ if permissions are granted
        _loadBundledKMZ();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some permissions were denied. App functionality may be limited.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('Error requesting permissions: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error requesting permissions: $e')),
      );
    }
  }

  Future<void> _pickKMZFile() async {
    if (!_permissionsGranted) {
      await _requestPermissions();
      if (!_permissionsGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions are required to pick files')),
        );
        return;
      }
    }
    
    try {
      final XFile? pickedFile = await _picker.pickMedia();
      
      if (pickedFile != null) {
        setState(() {
          _selectedFile = pickedFile;
          _isLoading = true;
        });
        
        await _processKMZFile(pickedFile.path);
        
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking KMZ file: $e')),
      );
    }
  }

  Future<void> _loadBundledKMZ() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // Get app directory path
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/OFC_Layer_LayerToKML.kmz';
      
      // Check if file exists first, if not, copy from assets
      final file = File(filePath);
      if (!await file.exists()) {
        print("File doesn't exist, copying from assets...");
        try {
          // Load from assets using rootBundle
          final data = await rootBundle.load('assets/map_data/OFC_Layer_LayerToKML.kmz');
          
          // Write the file to the documents directory
          await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          print("File copied successfully to: $filePath");
        } catch (e) {
          print('Error copying bundled KMZ file: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error copying bundled KMZ file: $e')),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }
      
      // Now process the file
      if (await file.exists()) {
        print("Processing file at: $filePath");
        await _processKMZFile(filePath);
      } else {
        print("File still doesn't exist after copy attempt");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bundled KMZ file not found')),
        );
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading bundled KMZ file: $e');
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading bundled KMZ file: $e')),
      );
    }
  }

  Future<void> _processKMZFile(String filePath) async {
    try {
      print("Starting to process KMZ file: $filePath");
      // Read KMZ file
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      print("File read success, size: ${bytes.length} bytes");
      
      // Decompress KMZ (which is a ZIP file containing KML)
      final archive = ZipDecoder().decodeBytes(bytes);
      print("Archive decoded, contains ${archive.files.length} files");
      
      // List all files in archive for debugging
      for (var file in archive.files) {
        print("Archive contains: ${file.name}");
      }
      
      // Find the KML file (usually doc.kml)
      ArchiveFile? kmlFile;
      try {
        kmlFile = archive.findFile('doc.kml') ?? 
                 archive.files.firstWhere((file) => file.name.toLowerCase().endsWith('.kml'));
        print("Found KML file: ${kmlFile.name}");
      } catch (e) {
        print("No KML file found in archive");
        throw Exception('No KML file found in the KMZ archive');
      }
      
      if (kmlFile == null) {
        print("KML file is null");
        throw Exception('No KML file found in the KMZ archive');
      }
      
      // Get KML content
      final kmlContent = String.fromCharCodes(kmlFile.content as List<int>);
      print("KML content length: ${kmlContent.length} characters");
      print("KML content preview: ${kmlContent.substring(0, min(200, kmlContent.length))}...");
      
      // Parse KML
      await _parseKML(kmlContent);
      
      // Force map update
      _forceMapUpdate();
      
      print("KMZ processing completed");
      
    } catch (e) {
      print('Error processing KMZ file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing KMZ file: $e')),
      );
    }
  }

  Future<void> _parseKML(String kmlContent) async {
    try {
      print("Starting to parse KML content...");
      final document = XmlDocument.parse(kmlContent);
      
      // Temporary collections
      final Set<Polygon> polygons = {};
      final Set<Polyline> polylines = {};
      final Set<Marker> markers = {};
      
      // Process Placemarks
      final placemarks = document.findAllElements('Placemark');
      print("Found ${placemarks.length} placemarks");
      
      for (final placemark in placemarks) {
        // Get name if available
        final nameElement = placemark.findElements('name').firstOrNull;
        final name = nameElement?.innerText ?? 'Unnamed';
        print("Processing placemark: $name");
        
        // Process Polygons
        final polygonElements = placemark.findAllElements('Polygon');
        print("Found ${polygonElements.length} polygons in placemark");
        for (final polygonElement in polygonElements) {
          final coordinates = _getCoordinatesFromPolygon(polygonElement);
          print("Polygon coordinates count: ${coordinates.length}");
          if (coordinates.isNotEmpty) {
            polygons.add(
              Polygon(
                polygonId: PolygonId('polygon_${polygons.length}'),
                points: coordinates,
                fillColor: Colors.blue.withOpacity(0.3),
                strokeColor: Colors.blue,
                strokeWidth: 2,
              ),
            );
          }
        }
        
        // Process LineStrings (Polylines)
        final lineElements = placemark.findAllElements('LineString');
        print("Found ${lineElements.length} linestrings in placemark");
        for (final lineElement in lineElements) {
          final coordinates = _getCoordinatesFromElement(lineElement);
          print("LineString coordinates count: ${coordinates.length}");
          if (coordinates.isNotEmpty) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('polyline_${polylines.length}'),
                points: coordinates,
                color: Colors.red,
                width: 3,
              ),
            );
          }
        }
        
        // Process Points (Markers)
        final pointElements = placemark.findAllElements('Point');
        print("Found ${pointElements.length} points in placemark");
        for (final pointElement in pointElements) {
          final coordinates = _getCoordinatesFromElement(pointElement);
          print("Point coordinates count: ${coordinates.length}");
          if (coordinates.isNotEmpty) {
            markers.add(
              Marker(
                markerId: MarkerId('marker_${markers.length}'),
                position: coordinates.first,
                infoWindow: InfoWindow(title: name),
              ),
            );
          }
        }
      }
      
      print("Setting state with: ${polygons.length} polygons, ${polylines.length} polylines, ${markers.length} markers");
      setState(() {
        _polygons = polygons;
        _polylines = polylines;
        _markers = markers;
      });
      
    } catch (e) {
      print('Error parsing KML content: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing KML content: $e')),
      );
    }
  }

  List<LatLng> _getCoordinatesFromPolygon(XmlElement polygonElement) {
    try {
      // Find outer boundary
      final outerBoundary = polygonElement.findElements('outerBoundaryIs').firstOrNull;
      if (outerBoundary == null) {
        print("No outerBoundaryIs element found");
        return [];
      }
      
      final linearRing = outerBoundary.findElements('LinearRing').firstOrNull;
      if (linearRing == null) {
        print("No LinearRing element found");
        return [];
      }
      
      return _getCoordinatesFromElement(linearRing);
    } catch (e) {
      print('Error parsing polygon: $e');
      return [];
    }
  }

  List<LatLng> _getCoordinatesFromElement(XmlElement element) {
    try {
      final coordinatesElement = element.findElements('coordinates').firstOrNull;
      if (coordinatesElement == null) {
        print("No coordinates element found");
        return [];
      }
      
      final coordinatesText = coordinatesElement.innerText.trim();
      if (coordinatesText.isEmpty) {
        print("Coordinates text is empty");
        return [];
      }
      
      print("Raw coordinates: ${coordinatesText.substring(0, min(100, coordinatesText.length))}...");
      
      final coordinates = <LatLng>[];
      
      // Parse coordinates (format: lon,lat,alt lon,lat,alt ...)
      final coordPairs = coordinatesText.split(' ');
      print("Found ${coordPairs.length} coordinate pairs");
      
      for (final pair in coordPairs) {
        if (pair.trim().isEmpty) continue;
        
        final parts = pair.split(',');
        if (parts.length >= 2) {
          final lon = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          
          if (lon != null && lat != null) {
            coordinates.add(LatLng(lat, lon));
          } else {
            print("Failed to parse lat/lon from: $pair");
          }
        } else {
          print("Invalid coordinate pair format: $pair");
        }
      }
      
      print("Successfully parsed ${coordinates.length} coordinates");
      return coordinates;
    } catch (e) {
      print('Error parsing coordinates: $e');
      return [];
    }
  }

  void _moveToFeatures() {
    if (_mapController == null) {
      print("Cannot move to features: map controller is null");
      return;
    }
    
    // Collect all points to calculate bounds
    final List<LatLng> allPoints = [];
    
    for (final polygon in _polygons) {
      allPoints.addAll(polygon.points);
    }
    
    for (final polyline in _polylines) {
      allPoints.addAll(polyline.points);
    }
    
    for (final marker in _markers) {
      allPoints.add(marker.position);
    }
    
    if (allPoints.isEmpty) {
      print("No points to move to");
      return;
    }
    
    print("Moving camera to show ${allPoints.length} points");
    
    // Calculate bounds
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;
    
    for (final point in allPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    
    // Create bounds with padding
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    
    // Move camera to show all features with padding
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  void _forceMapUpdate() {
    if (_mapController != null) {
      setState(() {
        // Force rebuild
      });
      // Move to features with a slight delay to ensure map is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _moveToFeatures();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('KMZ Map Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: _pickKMZFile,
            tooltip: 'Open KMZ File',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            mapType: MapType.normal,
            myLocationButtonEnabled: true,
            myLocationEnabled: _permissionsGranted,
            zoomControlsEnabled: true,
            polygons: _polygons,
            polylines: _polylines,
            markers: _markers,
            onMapCreated: (controller) {
              setState(() {
                _mapController = controller;
              });
              print("Map controller created");
            },
          ),
          if (_selectedFile != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'File: ${_selectedFile!.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickKMZFile,
        tooltip: 'Pick KMZ File',
        child: const Icon(Icons.upload_file),
      ),
    );
  }
}