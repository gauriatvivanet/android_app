import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Upload Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const FileUploadPage(),
    );
  }
}

class FileUploadPage extends StatefulWidget {
  const FileUploadPage({super.key});

  @override
  State<FileUploadPage> createState() => _FileUploadPageState();
}

class _FileUploadPageState extends State<FileUploadPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  bool _isUploading = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      
      if (pickedFile != null) {
        setState(() {
          _selectedFile = pickedFile;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e')),
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      final XFile? pickedFile = await _picker.pickMedia();
      
      if (pickedFile != null) {
        setState(() {
          _selectedFile = pickedFile;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e')),
      );
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Simulate file upload with a delay
      await Future.delayed(const Duration(seconds: 2));
      
      // Here you would implement actual file upload to a server
      // For example using http package:
      // final request = http.MultipartRequest('POST', Uri.parse('your-upload-url'));
      // request.files.add(await http.MultipartFile.fromPath('file', _selectedFile!.path));
      // final response = await request.send();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('File Upload'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_upload,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 20),
              const Text(
                'Upload File',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              if (_selectedFile != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _selectedFile!.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.file_present),
                    label: const Text('Select File'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadFile,
                icon: _isUploading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ) 
                  : const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? 'Uploading...' : 'Upload'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}