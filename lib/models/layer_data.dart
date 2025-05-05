import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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