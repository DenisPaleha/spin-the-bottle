import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  final List<String> _searchPhrases = [
    "Listening to the air...",
    "Spinner is sleeping...",
    "Spin to activate...",
  ];

  int _searchPhraseIndex = 0;
  bool _isScanningOrConnecting = false;
  bool _isRunning = false;

  StreamSubscription? _scanResultsSubscription;

  final Function(String status) onStatusChanged;
  final Function(int inboundValue) onDataReceived;

  BluetoothService({
    required this.onStatusChanged,
    required this.onDataReceived,
  });

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _startAutoConnectionLoop();
  }

  void stop() {
    _isRunning = false;
    _isScanningOrConnecting = false;
    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;
    FlutterBluePlus.stopScan();
  }

  void _startAutoConnectionLoop() async {
    while (_isRunning) {
      await Future.delayed(const Duration(seconds: 1));
      if (!_isRunning) break;

      if (_isScanningOrConnecting) continue;
      _isScanningOrConnecting = true;

      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        onStatusChanged("Turn on Bluetooth\nin notification shade!");
        _isScanningOrConnecting = false;
        continue;
      }

      onStatusChanged(_searchPhrases[_searchPhraseIndex]);

      try {
        await FlutterBluePlus.startScan(
          androidUsesFineLocation: true,
          withNames: ["Smart-Spinner"],
        );

        await _scanResultsSubscription?.cancel();
        _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
          for (ScanResult r in results) {
            if (r.device.platformName == "Smart-Spinner") {
              final manufacturerData = r.advertisementData.manufacturerData;

              if (manufacturerData.containsKey(65535)) {
                List<int>? bytes = manufacturerData[65535];

                if (bytes != null && bytes.length >= 4) {
                  int currentInboundValue =
                  bytes[0] |
                  (bytes[1] << 8) |
                  (bytes[2] << 16) |
                  (bytes[3] << 24);

                  _searchPhraseIndex = 0;
                  onDataReceived(currentInboundValue);
                }
              }
            }
          }
        });

        await Future.delayed(const Duration(minutes: 10));
      } catch (e) {
        _searchPhraseIndex = (_searchPhraseIndex + 1) % _searchPhrases.length;
        await FlutterBluePlus.stopScan();
        _isScanningOrConnecting = false;
      }
    }
  }

  void dispose() {
    stop();
  }
}