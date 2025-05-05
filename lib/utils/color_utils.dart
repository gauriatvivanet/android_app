import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/layer_data.dart';

class ColorUtils {
  static final List<Color> availableColors = [
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
  
  static bool isColorUsed(Color colorToCheck, List<LayerData> layers) {
    // Iterate through all layers and check if the color is used
    for (var layer in layers) {
      if (layer.color == colorToCheck) {
        return true; // Color is already used
      }
    }
    return false; // Color is not used
  }

  static Color getUnusedColor(List<LayerData> layers) {
    for (var color in availableColors) {
      if (!isColorUsed(color, layers)) {
        return color; // Return the first unused color
      }
    }
    // If all colors are used, return a fallback color
    return Colors.grey; // Fallback color
  }
  
  // Convert Color to marker hue
  static double getHueForColor(Color color) {
    // Mapping common colors to hues
    if (color == Colors.red) return BitmapDescriptor.hueRed;
    if (color == Colors.green) return BitmapDescriptor.hueGreen;
    if (color == Colors.blue) return BitmapDescriptor.hueBlue;
    if (color == Colors.orange) return BitmapDescriptor.hueOrange;
    if (color == Colors.yellow) return BitmapDescriptor.hueYellow;
    if (color == Colors.cyan) return BitmapDescriptor.hueCyan;
    if (color == Colors.pink) return BitmapDescriptor.hueRose;
    if (color == Colors.purple) return BitmapDescriptor.hueViolet;
    
    // Fallback
    return BitmapDescriptor.hueAzure;
  }
}