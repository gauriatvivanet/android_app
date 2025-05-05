import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import '../models/layer_data.dart';
import '../utils/color_utils.dart';

class KmzProcessor {
  static String splitOnLastOccurrence(String input, String delimiter) {
    // Check if the input string contains the delimiter
    if (!input.contains(delimiter)) {
      return input; // Simply return the original string if delimiter isn't found
    }

    // Find the last occurrence of the delimiter
    final lastIndex = input.lastIndexOf(delimiter);

    // Return the substring up to the last occurrence of the delimiter
    return input.substring(0, lastIndex);
  }

  static Future<void> processKMZFile(String filePath, LayerData layer) async {
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
      await parseKML(kmlContent, layer);
      
    } catch (e) {
      print('Error processing KMZ file for layer ${layer.name}: $e');
    }
  }

  static Future<void> parseKML(String kmlContent, LayerData layer) async {
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
          final coordinates = getCoordinatesFromPolygon(polygonElement);
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
          final coordinates = getCoordinatesFromElement(lineElement);
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
          final coordinates = getCoordinatesFromElement(pointElement);
          if (coordinates.isNotEmpty) {
            markers.add(
              Marker(
                markerId: MarkerId('${layer.name}_marker_${markers.length}'),
                position: coordinates.first,
                infoWindow: InfoWindow(title: name, snippet: layer.name),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  ColorUtils.getHueForColor(layer.color)
                ),
              ),
            );
          }
        }
      }
      
      print("Parsed for layer ${layer.name}: ${polygons.length} polygons, ${polylines.length} polylines, ${markers.length} markers");
      
      // Update the layer with the parsed geometry
      layer.polygons = polygons;
      layer.polylines = polylines;
      layer.markers = markers;
      
    } catch (e) {
      print('Error parsing KML content for layer ${layer.name}: $e');
    }
  }

  static List<LatLng> getCoordinatesFromPolygon(XmlElement polygonElement) {
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
      
      return getCoordinatesFromElement(linearRing);
    } catch (e) {
      print('Error parsing polygon: $e');
      return [];
    }
  }

  static List<LatLng> getCoordinatesFromElement(XmlElement element) {
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
}