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
import 'package:file_picker/file_picker.dart';

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
  final String filePath;
  bool isVisible;
  Set<Polygon> polygons = {};
  Set<Polyline> polylines = {};
  Set<Marker> markers = {};
  Color color;

  LayerData({
    required this.name,
    required this.filePath,
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
  bool _isLoading = false;
  GoogleMapController? _mapController;
  bool _permissionsGranted = false;
  bool _layersPanelOpen = false;
  
  // List to store uploaded map layers
  final List<LayerData> _layers = [];
  
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
    target: LatLng(28.6139, 77.2090), // Default to New Delhi
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.storage,
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

  Future<void> _pickKMZFiles() async {
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
      setState(() {
        _isLoading = true;
      });
      
      // Use FilePicker to pick multiple KMZ files
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kmz', 'kml'],
        allowMultiple: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        // Process each selected file
        for (final file in result.files) {
          if (file.path != null) {
            // Create a random color for this layer
            final randomColor = _getRandomColor();
            
            // Create a new layer for this file
            final newLayer = LayerData(
              name: file.name,
              filePath: file.path!,
              isVisible: true,
              color: randomColor,
            );
            
            // Process the KMZ file
            await _processKMZFile(file.path!, newLayer);
            
            // Add the layer to our list
            setState(() {
              _layers.add(newLayer);
            });
          }
        }
        
        // Move the map to show the loaded features
        _forceMapUpdate();
      }
      
      setState(() {
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking KMZ files: $e')),
      );
    }
  }

  // Generate a random color for a new layer
  Color _getRandomColor() {
    final random = Random();
    final colorOptions = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.amber,
      Colors.indigo,
      Colors.cyan,
      Colors.brown,
      Colors.deepOrange,
    ];
    
    return colorOptions[random.nextInt(colorOptions.length)];
  }

  Future<void> _processKMZFile(String filePath, LayerData layer) async {
    try {
      print("Starting to process KMZ file for layer ${layer.name}: $filePath");
      // Read KMZ file
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      print("File read success, size: ${bytes.length} bytes");
      
      // Check if it's a KML file (plain text XML) or KMZ (zip archive)
      if (filePath.toLowerCase().endsWith('.kml')) {
        // It's a KML file, no need to decompress
        final kmlContent = String.fromCharCodes(bytes);
        await _parseKML(kmlContent, layer);
      } else {
        // It's a KMZ file, need to decompress
        try {
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
          print('Error decompressing KMZ file: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error decompressing KMZ file: $e')),
          );
        }
      }
    } catch (e) {
      print('Error processing KMZ file for layer ${layer.name}: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing file ${layer.name}: $e')),
      );
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

  void _clearAllLayers() {
    setState(() {
      _layers.clear();
    });
    
    // Reset map view
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(_initialCameraPosition),
      );
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
            icon: const Icon(Icons.upload_file),
            onPressed: _pickKMZFiles,
            tooltip: 'Upload KMZ Files',
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
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _layers.isEmpty ? null : _clearAllLayers,
            tooltip: 'Clear All Layers',
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
          if (_layers.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.upload_file,
                    size: 64,
                    color: Colors.grey.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Upload KMZ/KML files to display on map',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _pickKMZFiles,
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Upload Files'),
                  ),
                ],
              ),
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
                    if (_layers.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            'No layers loaded',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      )
                    else
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
                              title: Text(
                                layer.name,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton.icon(
                        onPressed: _pickKMZFiles,
                        icon: const Icon(Icons.add),
                        label: const Text('Add More Layers'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                        ),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading Map Data...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _pickKMZFiles,
            tooltip: 'Upload KMZ Files',
            heroTag: 'uploadFiles',
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