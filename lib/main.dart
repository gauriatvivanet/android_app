import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:math';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-Layer KMZ Map Viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapPage(),
    );
  }
}

class LayerData {
  final String name;
  final String assetPath;
  bool isVisible;
  Set<Polygon> polygons = {};
  Set<Polyline> polylines = {};
  Set<Marker> markers = {};
  Color color;

  LayerData({
    required this.name,
    required this.assetPath,
    this.isVisible = false,
    this.color = Colors.blue,
  });
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  GoogleMapController? _mapController;
  bool _permissionsGranted = false;
  bool _layersPanelOpen = false;
  
  // All available map layers
  final List<LayerData> _layers = [];

  final List<Color> _colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.indigo,
  ];
  
  bool isColorUsed(Color colorToCheck, List<LayerData> layers) {
    // Iterate through all layers and check if the color is used
    for (var layer in layers) {
      if (layer.color == colorToCheck) {
        return true; // Color is already used
      }
    }

    return false; // Color is not used
  }

  Color getUnusedColor(List<LayerData> layers) {
    for (var color in _colors) {
      if (!isColorUsed(color, layers)) {
        return color; // Return the first unused color
      }
    }

    // If all colors are used, return a fallback color or generate a random one
    return Colors.grey; // Fallback color
  }

  // Computed sets of visible polygons, polylines, and markers
  Set<Polygon> get _visiblePolygons {
    final result = <Polygon>{};
    for (final layer in _layers) {
      if (layer.isVisible) {
        result.addAll(layer.polygons);
      }
    }
    return result;
  }
  
  Set<Polyline> get _visiblePolylines {
    final result = <Polyline>{};
    for (final layer in _layers) {
      if (layer.isVisible) {
        result.addAll(layer.polylines);
      }
    }
    return result;
  }
  
  Set<Marker> get _visibleMarkers {
    final result = <Marker>{};
    for (final layer in _layers) {
      if (layer.isVisible) {
        result.addAll(layer.markers);
      }
    }
    return result;
  }
  
  // Default camera position
  final CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    
    // Load all layers with a slight delay to ensure initialization
    Future.delayed(const Duration(seconds: 1), () {
      _loadAllLayers();
    });
  }

  Future<void> _requestPermissions() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.photos,
        Permission.camera,
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
      
      if (!allGranted) {
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

  Future<void> _loadAllLayers() async {
    setState(() {
      _isLoading = true;
    });
    
    for (final layer in _layers) {
      await _loadLayerFromAssets(layer);
    }
    
    setState(() {
      _isLoading = false;
      // Enable all layers by default
      for (var layer in _layers) {
        layer.isVisible = true;
      }
    });
    
    // Force map update and zoom to visible features
    _forceMapUpdate();
  }

  Future<void> _loadLayerFromAssets(LayerData layer) async {
    try {
      print("Loading layer: ${layer.name} from ${layer.assetPath}");
      
      // Get app directory path
      final directory = await getApplicationDocumentsDirectory();
      final fileName = layer.assetPath.split('/').last;
      final filePath = '${directory.path}/$fileName';
      
      // Check if file exists first, if not, copy from assets
      final file = File(filePath);
      if (!await file.exists()) {
        print("File doesn't exist, copying from assets...");
        try {
          // Load from assets using rootBundle
          final data = await rootBundle.load(layer.assetPath);
          
          // Write the file to the documents directory
          await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          print("File copied successfully to: $filePath");
        } catch (e) {
          print('Error copying KMZ file for layer ${layer.name}: $e');
          return;
        }
      }
      
      // Now process the file
      if (await file.exists()) {
        print("Processing file for layer ${layer.name} at: $filePath");
        await _processKMZFile(filePath, layer);
      } else {
        print("File still doesn't exist after copy attempt for layer ${layer.name}");
      }
    } catch (e) {
      print('Error loading layer ${layer.name}: $e');
    }
  }

  String splitOnLastOccurrence(String input, String delimiter) {
    // Check if the input string contains the delimiter
    if (!input.contains(delimiter)) {
      return input; // Simply return the original string if delimiter isn't found
    }

    // Find the last occurrence of the delimiter
    final lastIndex = input.lastIndexOf(delimiter);

    // Return the substring up to the last occurrence of the delimiter
    return input.substring(0, lastIndex);
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
      
      Color newColor = getUnusedColor(_layers);

      if (pickedFile != null) {
        setState(() {
          _isLoading = true;
        });
        
        // Create a new custom layer for the picked file
        final customLayer = LayerData(
          name:
              splitOnLastOccurrence(pickedFile.name, "_").replaceAll("_", " "),
          assetPath: pickedFile.path,
          isVisible: true,
          color: newColor,
        );
        
        await _processKMZFile(pickedFile.path, customLayer);
        
        setState(() {
          _layers.add(customLayer);
          _isLoading = false;
        });
        
        _forceMapUpdate();
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

  Future<void> _processKMZFile(String filePath, LayerData layer) async {
    try {
      print("Starting to process KMZ file for layer ${layer.name}: $filePath");
      // Read KMZ file
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      print("File read success, size: ${bytes.length} bytes");
      
      // Decompress KMZ (which is a ZIP file containing KML)
      final archive = ZipDecoder().decodeBytes(bytes);
      print("Archive decoded, contains ${archive.files.length} files");
      
      // Find the KML file (usually doc.kml)
      ArchiveFile? kmlFile;
      try {
        kmlFile = archive.findFile('doc.kml') ?? 
                 archive.files.firstWhere((file) => file.name.toLowerCase().endsWith('.kml'));
        print("Found KML file: ${kmlFile.name}");
      } catch (e) {
        print("No KML file found in archive for layer ${layer.name}");
        return;
      }
      
      if (kmlFile == null) {
        print("KML file is null for layer ${layer.name}");
        return;
      }
      
      // Get KML content
      final kmlContent = String.fromCharCodes(kmlFile.content as List<int>);
      print("KML content length: ${kmlContent.length} characters");
      
      // Parse KML for this layer
      await _parseKML(kmlContent, layer);
      
    } catch (e) {
      print('Error processing KMZ file for layer ${layer.name}: $e');
    }
  }

  Future<void> _parseKML(String kmlContent, LayerData layer) async {
    try {
      print("Starting to parse KML content for layer ${layer.name}...");
      final document = XmlDocument.parse(kmlContent);
      
      // Temporary collections
      final Set<Polygon> polygons = {};
      final Set<Polyline> polylines = {};
      final Set<Marker> markers = {};
      
      // Process Placemarks
      final placemarks = document.findAllElements('Placemark');
      print("Found ${placemarks.length} placemarks in layer ${layer.name}");
      
      for (final placemark in placemarks) {
        // Get name if available
        final nameElement = placemark.findElements('name').firstOrNull;
        final name = nameElement?.innerText ?? 'Unnamed';
        
        // Process Polygons
        final polygonElements = placemark.findAllElements('Polygon');
        for (final polygonElement in polygonElements) {
          final coordinates = _getCoordinatesFromPolygon(polygonElement);
          if (coordinates.isNotEmpty) {
            polygons.add(
              Polygon(
                polygonId: PolygonId('${layer.name}_polygon_${polygons.length}'),
                points: coordinates,
                fillColor: layer.color.withOpacity(0.3),
                strokeColor: layer.color,
                strokeWidth: 2,
              ),
            );
          }
        }
        
        // Process LineStrings (Polylines)
        final lineElements = placemark.findAllElements('LineString');
        for (final lineElement in lineElements) {
          final coordinates = _getCoordinatesFromElement(lineElement);
          if (coordinates.isNotEmpty) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('${layer.name}_polyline_${polylines.length}'),
                points: coordinates,
                color: layer.color,
                width: 3,
              ),
            );
          }
        }
        
        // Process Points (Markers)
        final pointElements = placemark.findAllElements('Point');
        for (final pointElement in pointElements) {
          final coordinates = _getCoordinatesFromElement(pointElement);
          if (coordinates.isNotEmpty) {
            markers.add(
              Marker(
                markerId: MarkerId('${layer.name}_marker_${markers.length}'),
                position: coordinates.first,
                infoWindow: InfoWindow(title: name, snippet: layer.name),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  _getHueForColor(layer.color)
                ),
              ),
            );
          }
        }
      }
      
      print("Parsed for layer ${layer.name}: ${polygons.length} polygons, ${polylines.length} polylines, ${markers.length} markers");
      
      // Update the layer with the parsed geometry
      setState(() {
        layer.polygons = polygons;
        layer.polylines = polylines;
        layer.markers = markers;
      });
      
    } catch (e) {
      print('Error parsing KML content for layer ${layer.name}: $e');
    }
  }

  // Convert Color to marker hue
  double _getHueForColor(Color color) {
    // Simplified approach, mapping some common colors to hues
    if (color == Colors.red) return BitmapDescriptor.hueRed;
    if (color == Colors.green) return BitmapDescriptor.hueGreen;
    if (color == Colors.blue) return BitmapDescriptor.hueBlue;
    if (color == Colors.orange) return BitmapDescriptor.hueOrange;
    if (color == Colors.yellow) return BitmapDescriptor.hueYellow;
    if (color == Colors.cyan) return BitmapDescriptor.hueCyan;
    if (color == Colors.pink) return BitmapDescriptor.hueRose;
    if (color == Colors.purple) return BitmapDescriptor.hueViolet;
    
    // Fallback to azure for other colors
    return BitmapDescriptor.hueAzure;
  }

  List<LatLng> _getCoordinatesFromPolygon(XmlElement polygonElement) {
    try {
      // Find outer boundary
      final outerBoundary = polygonElement.findElements('outerBoundaryIs').firstOrNull;
      if (outerBoundary == null) {
        return [];
      }
      
      final linearRing = outerBoundary.findElements('LinearRing').firstOrNull;
      if (linearRing == null) {
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
        return [];
      }
      
      final coordinatesText = coordinatesElement.innerText.trim();
      if (coordinatesText.isEmpty) {
        return [];
      }
      
      final coordinates = <LatLng>[];
      
      // Parse coordinates (format: lon,lat,alt lon,lat,alt ...)
      final coordPairs = coordinatesText.split(' ');
      
      for (final pair in coordPairs) {
        if (pair.trim().isEmpty) continue;
        
        final parts = pair.split(',');
        if (parts.length >= 2) {
          final lon = double.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          
          if (lon != null && lat != null) {
            coordinates.add(LatLng(lat, lon));
          }
        }
      }
      
      return coordinates;
    } catch (e) {
      print('Error parsing coordinates: $e');
      return [];
    }
  }

  void _toggleLayerVisibility(int index) {
    setState(() {
      _layers[index].isVisible = !_layers[index].isVisible;
    });
    _forceMapUpdate();
  }

  void _moveToFeatures() {
    if (_mapController == null) {
      return;
    }
    
    // Collect all points from visible layers to calculate bounds
    final List<LatLng> allPoints = [];
    
    for (final layer in _layers) {
      if (layer.isVisible) {
        for (final polygon in layer.polygons) {
          allPoints.addAll(polygon.points);
        }
        
        for (final polyline in layer.polylines) {
          allPoints.addAll(polyline.points);
        }
        
        for (final marker in layer.markers) {
          allPoints.add(marker.position);
        }
      }
    }
    
    if (allPoints.isEmpty) {
      print("No visible features found to move the camera to");
      return;
    }
    
    print("Found ${allPoints.length} points across all visible layers");
    
    // Calculate bounds
    double minLat = 90.0; // Start with extremes
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;
    
    for (final point in allPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    
    print("Calculated bounds: SW($minLat, $minLng), NE($maxLat, $maxLng)");
    
    // Create bounds with padding
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    
    // Move camera to show all features with padding
    try {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );
      print("Camera updated to show all features");
    } catch (e) {
      print("Error updating camera: $e");
      // Fallback - move to center of bounds
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(centerLat, centerLng),
            zoom: 10.0,
          ),
        ),
      );
      print("Used fallback camera position to center of bounds");
    }
  }

  void _forceMapUpdate() {
    if (_mapController != null) {
      setState(() {
        // Force rebuild
      });
      // Move to features with a slight delay to ensure map is ready
      Future.delayed(const Duration(milliseconds: 1000), () {
        _moveToFeatures();
        
        // Print visible features for debugging
        print("Visible polygons: ${_visiblePolygons.length}");
        print("Visible polylines: ${_visiblePolylines.length}");
        print("Visible markers: ${_visibleMarkers.length}");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Multi-Layer KMZ Map Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: _pickKMZFile,
            tooltip: 'Open KMZ File',
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: () {
              setState(() {
                _layersPanelOpen = !_layersPanelOpen;
              });
            },
            tooltip: 'Toggle Layers Panel',
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
            polygons: _visiblePolygons,
            polylines: _visiblePolylines,
            markers: _visibleMarkers,
            onMapCreated: (controller) {
              setState(() {
                _mapController = controller;
              });
              print("Map controller created");
            },
          ),
          if (_layersPanelOpen)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 250,
              child: Container(
                color: Colors.white,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Theme.of(context).colorScheme.inversePrimary,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Map Layers',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _layersPanelOpen = false;
                              });
                            },
                            tooltip: 'Close Panel',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _layers.length,
                        itemBuilder: (context, index) {
                          final layer = _layers[index];
                          return ListTile(
                            leading: Icon(
                              Icons.layers,
                              color: layer.color,
                            ),
                            title: Text(layer.name),
                            trailing: Switch(
                              value: layer.isVisible,
                              activeColor: layer.color,
                              onChanged: (value) {
                                _toggleLayerVisibility(index);
                              },
                            ),
                            onTap: () {
                              _toggleLayerVisibility(index);
                            },
                          );
                        },
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _pickKMZFile,
            tooltip: 'Pick KMZ File',
            heroTag: 'pickFile',
            child: const Icon(Icons.upload_file),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () {
              setState(() {
                _layersPanelOpen = !_layersPanelOpen;
              });
            },
            tooltip: 'Toggle Layers',
            heroTag: 'toggleLayers',
            child: const Icon(Icons.layers),
          ),
        ],
      ),
    );
  }
}