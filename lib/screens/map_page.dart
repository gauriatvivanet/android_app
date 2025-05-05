import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import '../models/layer_data.dart';
import '../services/kmz_processor.dart';
import '../utils/color_utils.dart';

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
        await KmzProcessor.processKMZFile(filePath, layer);
      } else {
        print("File still doesn't exist after copy attempt for layer ${layer.name}");
      }
    } catch (e) {
      print('Error loading layer ${layer.name}: $e');
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
      
      Color newColor = ColorUtils.getUnusedColor(_layers);

      if (pickedFile != null) {
        setState(() {
          _isLoading = true;
        });
        
        // Create a new custom layer for the picked file
        final customLayer = LayerData(
          name: KmzProcessor.splitOnLastOccurrence(pickedFile.name, "_").replaceAll("_", " "),
          assetPath: pickedFile.path,
          isVisible: true,
          color: newColor,
        );
        
        await KmzProcessor.processKMZFile(pickedFile.path, customLayer);
        
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