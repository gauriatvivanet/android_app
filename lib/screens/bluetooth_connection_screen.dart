import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothConnectionScreen extends StatefulWidget {
  const BluetoothConnectionScreen({super.key});

  @override
  State<BluetoothConnectionScreen> createState() =>
      _BluetoothConnectionScreenState();
}

class _BluetoothConnectionScreenState extends State<BluetoothConnectionScreen> {
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  BluetoothDevice? _connectedDevice;
  List<BluetoothService> _services = [];

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    // Check if Bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth not supported on this device')),
        );
      }
      return;
    }

    // Request necessary permissions
    await _requestPermissions();

    // Start scanning
    _startScan();
  }

  Future<void> _requestPermissions() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      // For Android 12+ (API level 31+) need BLUETOOTH_SCAN and BLUETOOTH_CONNECT
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    } else {
      // For iOS
      await Permission.bluetooth.request();
    }
  }

  void _startScan() async {
    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (!_devices.contains(result.device)) {
            setState(() {
              _devices.add(result.device);
            });
          }
        }
      });

      // Listen for scan completion
      FlutterBluePlus.isScanning.listen((isScanning) {
        setState(() {
          _isScanning = isScanning;
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting scan: $e')),
        );
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      setState(() {
        _connectedDevice = device;
      });

      // Discover services
      _services = await device.discoverServices();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${device.name ?? 'Unknown Device'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting to device: $e')),
        );
      }
    }
  }

  Future<void> _disconnectFromDevice() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        setState(() {
          _connectedDevice = null;
          _services.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Disconnected')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error disconnecting: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Bluetooth Devices'),
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _disconnectFromDevice,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_connectedDevice != null) ...[
            Container(
              color: Colors.green.shade100,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Connected: ${_connectedDevice!.name ?? 'Unknown Device'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton(
                    onPressed: _disconnectFromDevice,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),
            if (_services.isNotEmpty) _buildServicesView(),
          ],
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Devices:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                bool isConnected = _connectedDevice == device;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.bluetooth,
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                    title: Text(
                      device.name.isNotEmpty ? device.name : 'Unknown Device',
                      style: TextStyle(
                        fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text('ID: ${device.id}'),
                    trailing: isConnected
                        ? const Text(
                            'Connected',
                            style: TextStyle(color: Colors.green),
                          )
                        : ElevatedButton(
                            onPressed: () => _connectToDevice(device),
                            child: const Text('Connect'),
                          ),
                    onTap: isConnected ? null : () => _connectToDevice(device),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesView() {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Device Services:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _services.length,
                  itemBuilder: (context, index) {
                    final service = _services[index];
                    return ExpansionTile(
                      title: Text('Service: ${service.uuid.toString()}'),
                      children: service.characteristics.map((characteristic) {
                        return ListTile(
                          title: Text('Characteristic: ${characteristic.uuid.toString()}'),
                          subtitle: Text(
                            'Properties: ${_getCharacteristicProperties(characteristic)}',
                          ),
                          onTap: () {
                            _showCharacteristicDialog(characteristic);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCharacteristicProperties(BluetoothCharacteristic characteristic) {
    List<String> properties = [];
    if (characteristic.properties.read) properties.add('Read');
    if (characteristic.properties.write) properties.add('Write');
    if (characteristic.properties.notify) properties.add('Notify');
    if (characteristic.properties.indicate) properties.add('Indicate');
    return properties.join(', ');
  }

  void _showCharacteristicDialog(BluetoothCharacteristic characteristic) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Characteristic Actions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (characteristic.properties.read)
              ElevatedButton(
                onPressed: () => _readCharacteristic(characteristic),
                child: const Text('Read Value'),
              ),
            if (characteristic.properties.write)
              ElevatedButton(
                onPressed: () => _showWriteDialog(characteristic),
                child: const Text('Write Value'),
              ),
            if (characteristic.properties.notify)
              ElevatedButton(
                onPressed: () => _toggleNotify(characteristic),
                child: const Text('Toggle Notifications'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _readCharacteristic(BluetoothCharacteristic characteristic) async {
    try {
      final value = await characteristic.read();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Read Value'),
            content: Text('Value: $value'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading characteristic: $e')),
        );
      }
    }
  }

  void _showWriteDialog(BluetoothCharacteristic characteristic) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Write Value'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Enter value (e.g., "Hello" or "01:02:03:04")',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text;
              _writeCharacteristic(characteristic, value);
              Navigator.pop(context);
            },
            child: const Text('Write'),
          ),
        ],
      ),
    );
  }

  Future<void> _writeCharacteristic(BluetoothCharacteristic characteristic, String value) async {
    try {
      // Convert string to bytes (you may need to modify this based on your requirements)
      List<int> bytes = value.codeUnits;
      await characteristic.write(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully wrote to characteristic')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error writing to characteristic: $e')),
        );
      }
    }
  }

  Future<void> _toggleNotify(BluetoothCharacteristic characteristic) async {
    try {
      bool isNotifying = characteristic.isNotifying;
      await characteristic.setNotifyValue(!isNotifying);
      
      if (!isNotifying) {
        characteristic.value.listen((value) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Notification: $value')),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling notifications: $e')),
        );
      }
    }
  }
}