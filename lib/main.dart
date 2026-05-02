import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class DeviceItem {
  final String name;
  final String id;
  final String type;

  DeviceItem({
    required this.name,
    required this.id,
    required this.type,
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BluetoothScannerPage(),
    );
  }
}

/* ===========================
   PAGE 1: BLE + CLASSIC SCANNER
   =========================== */

class BluetoothScannerPage extends StatefulWidget {
  const BluetoothScannerPage({super.key});

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage> {
  static const MethodChannel classicChannel =
  MethodChannel('classic_bluetooth_scanner');

  final List<DeviceItem> bleDevices = [];
  final List<DeviceItem> classicDevices = [];
  final List<DeviceItem> pairedClassicDevices = [];

  StreamSubscription<List<ScanResult>>? bleSub;
  Timer? classicTimer;

  bool scanningBle = false;
  bool scanningClassic = false;

  @override
  void dispose() {
    bleSub?.cancel();
    classicTimer?.cancel();
    FlutterBluePlus.stopScan();
    classicChannel.invokeMethod('stopClassicScan');
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> loadPairedClassicDevices() async {
    final result = await classicChannel.invokeMethod('getPairedDevices');

    pairedClassicDevices.clear();

    for (final item in result) {
      pairedClassicDevices.add(
        DeviceItem(
          name: item['name'] ?? 'Unknown',
          id: item['address'] ?? '',
          type: item['type'] ?? 'Classic Paired',
        ),
      );
    }

    setState(() {});
  }

  Future<void> scanBle() async {
    await requestPermissions();

    bleDevices.clear();

    setState(() {
      scanningBle = true;
    });

    bleSub?.cancel();

    bleSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : 'Unknown BLE Device';

        final id = r.device.remoteId.str;

        if (!bleDevices.any((d) => d.id == id)) {
          bleDevices.add(
            DeviceItem(
              name: name,
              id: id,
              type: 'BLE',
            ),
          );
        }
      }

      setState(() {});
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      await Future.delayed(const Duration(seconds: 10));
    } catch (_) {}

    setState(() {
      scanningBle = false;
    });
  }

  Future<void> scanClassic() async {
    await requestPermissions();

    classicDevices.clear();

    setState(() {
      scanningClassic = true;
    });

    await classicChannel.invokeMethod('startClassicScan');

    classicTimer?.cancel();

    classicTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final result =
      await classicChannel.invokeMethod('getClassicScanResults');

      classicDevices.clear();

      for (final item in result) {
        classicDevices.add(
          DeviceItem(
            name: item['name'] ?? 'Unknown',
            id: item['address'] ?? '',
            type: item['type'] ?? 'Classic',
          ),
        );
      }

      setState(() {});
    });

    await Future.delayed(const Duration(seconds: 12));

    await classicChannel.invokeMethod('stopClassicScan');
    classicTimer?.cancel();

    setState(() {
      scanningClassic = false;
    });
  }

  Future<void> scanAll() async {
    await requestPermissions();
    await loadPairedClassicDevices();

    await Future.wait([
      scanBle(),
      scanClassic(),
    ]);
  }

  Future<void> handleDeviceTap(DeviceItem item) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectionTestPage(device: item),
      ),
    );
  }

  Widget buildDeviceList(String title, List<DeviceItem> devices) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Text('No devices found')
            else
              ...devices.map(
                    (d) => ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name),
                  subtitle: Text('${d.type}\n${d.id}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => handleDeviceTap(d),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = scanningBle || scanningClassic;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE + Classic Scanner'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: isScanning ? null : scanAll,
              icon: const Icon(Icons.search),
              label: Text(isScanning ? 'Scanning...' : 'Scan Devices'),
            ),
          ),
          buildDeviceList('BLE Devices', bleDevices),
          buildDeviceList('Classic Devices Found by Scan', classicDevices),
          buildDeviceList('Paired Classic Devices', pairedClassicDevices),
        ],
      ),
    );
  }
}

/* ===========================
   PAGE 2: CONNECTION TEST
   =========================== */

class ConnectionTestPage extends StatefulWidget {
  final DeviceItem device;

  const ConnectionTestPage({
    super.key,
    required this.device,
  });

  @override
  State<ConnectionTestPage> createState() => _ConnectionTestPageState();
}

class _ConnectionTestPageState extends State<ConnectionTestPage> {
  static const MethodChannel classicChannel =
  MethodChannel('classic_bluetooth_scanner');

  bool testing = true;
  bool success = false;
  String status = 'Starting...';

  bool hasWritableSerialCharacteristic = false;

  final Guid targetServiceUuid = Guid('ffe0');
  final Guid targetCharacteristicUuid = Guid('ffe1');

  @override
  void initState() {
    super.initState();
    testConnection();
  }

  bool isValidMac(String id) {
    final macRegex =
    RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$', caseSensitive: false);
    return macRegex.hasMatch(id);
  }

  Future<void> testConnection() async {
    if (widget.device.type == 'BLE') {
      await testBle();
    } else {
      await testClassic();
    }
  }

  Future<void> testBle() async {
    setState(() {
      testing = true;
      success = false;
      hasWritableSerialCharacteristic = false;
      status = 'Connecting via BLE and discovering services...';
    });

    BluetoothDevice? device;

    try {
      device = BluetoothDevice.fromId(widget.device.id);

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
        license: License.free,
      );

      final services = await device.discoverServices();

      String text = 'BLE connected.\n\n';

      for (final s in services) {
        text += 'Service: ${s.uuid}\n';

        for (final c in s.characteristics) {
          text += '  Characteristic: ${c.uuid}\n';
          text += '    read: ${c.properties.read}\n';
          text += '    write: ${c.properties.write}\n';
          text +=
          '    writeWithoutResponse: ${c.properties.writeWithoutResponse}\n';
          text += '    notify: ${c.properties.notify}\n\n';

          final serviceMatch = s.uuid.toString().toLowerCase() ==
              targetServiceUuid.toString().toLowerCase();

          final charMatch = c.uuid.toString().toLowerCase() ==
              targetCharacteristicUuid.toString().toLowerCase();

          if (serviceMatch &&
              charMatch &&
              (c.properties.write || c.properties.writeWithoutResponse)) {
            hasWritableSerialCharacteristic = true;
          }
        }
      }

      await device.disconnect();

      setState(() {
        testing = false;
        success = true;
        status = text;
      });
    } catch (e) {
      try {
        await device?.disconnect();
      } catch (_) {}

      setState(() {
        testing = false;
        success = false;
        hasWritableSerialCharacteristic = false;
        status = 'BLE failed:\n$e';
      });
    }
  }

  Future<void> testClassic() async {
    setState(() {
      testing = true;
      success = false;
      hasWritableSerialCharacteristic = false;
      status = 'Trying Classic Bluetooth connection...';
    });

    if (!isValidMac(widget.device.id)) {
      setState(() {
        testing = false;
        success = false;
        status = 'Classic connection failed: invalid MAC address.';
      });
      return;
    }

    try {
      final result = await classicChannel.invokeMethod(
        'connectClassic',
        {
          'address': widget.device.id,
        },
      );

      await classicChannel.invokeMethod('disconnectClassic');

      setState(() {
        testing = false;
        success = result['success'] == true;
        status = result['message'] ?? 'No message returned.';
      });
    } catch (e) {
      setState(() {
        testing = false;
        success = false;
        status = 'Classic connection failed:\n$e';
      });
    }
  }

  Future<void> retry() async {
    setState(() {
      testing = true;
      success = false;
      hasWritableSerialCharacteristic = false;
      status = 'Retrying...';
    });

    await testConnection();
  }

  @override
  Widget build(BuildContext context) {
    final icon = testing
        ? Icons.bluetooth_searching
        : success
        ? Icons.check_circle
        : Icons.error;

    final color = testing
        ? Colors.blue
        : success
        ? Colors.green
        : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Test'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 80, color: color),
              const SizedBox(height: 16),
              Text(
                widget.device.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(widget.device.type),
              const SizedBox(height: 8),
              SelectableText(
                widget.device.id,
                textAlign: TextAlign.center,
              ),
              const Divider(height: 32),
              if (testing) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  status,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 24),
              if (success && hasWritableSerialCharacteristic)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BleSerialPage(
                            deviceId: widget.device.id,
                            deviceName: widget.device.name,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.terminal),
                    label: const Text('Open BLE Serial Page'),
                  ),
                ),
              if (success && hasWritableSerialCharacteristic)
                const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: testing ? null : retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===========================
   PAGE 3: BLE SERIAL COMMUNICATION
   =========================== */

class BleSerialPage extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const BleSerialPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<BleSerialPage> createState() => _BleSerialPageState();
}

class _BleSerialPageState extends State<BleSerialPage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? serialChar;
  StreamSubscription<List<int>>? notifySub;

  bool connecting = false;
  bool connected = false;

  String logText = 'Not connected.';
  final TextEditingController messageController = TextEditingController();

  final Guid serviceUuid = Guid('ffe0');
  final Guid characteristicUuid = Guid('ffe1');

  @override
  void initState() {
    super.initState();
    connectBleSerial();
  }

  @override
  void dispose() {
    notifySub?.cancel();
    messageController.dispose();
    disconnect();
    super.dispose();
  }

  void addLog(String text) {
    if (!mounted) return;
    setState(() {
      logText += '\n$text';
    });
  }

  Future<void> connectBleSerial() async {
    setState(() {
      connecting = true;
      connected = false;
      serialChar = null;
      logText = 'Connecting to ${widget.deviceName}...';
    });

    try {
      device = BluetoothDevice.fromId(widget.deviceId);

      await device!.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
        license: License.free,
      );

      addLog('Connected.');

      final services = await device!.discoverServices();

      for (final service in services) {
        final serviceMatch = service.uuid.toString().toLowerCase() ==
            serviceUuid.toString().toLowerCase();

        if (serviceMatch) {
          for (final c in service.characteristics) {
            final charMatch = c.uuid.toString().toLowerCase() ==
                characteristicUuid.toString().toLowerCase();

            if (charMatch) {
              serialChar = c;
              break;
            }
          }
        }
      }

      if (serialChar == null) {
        throw Exception('FFE1 characteristic not found.');
      }

      addLog('Found FFE0 / FFE1 serial characteristic.');
      addLog('read: ${serialChar!.properties.read}');
      addLog('write: ${serialChar!.properties.write}');
      addLog('writeWithoutResponse: ${serialChar!.properties.writeWithoutResponse}');
      addLog('notify: ${serialChar!.properties.notify}');

      if (serialChar!.properties.notify) {
        await serialChar!.setNotifyValue(true);

        notifySub = serialChar!.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            final received = String.fromCharCodes(value);
            addLog('RX: $received');
          }
        });

        addLog('Notify enabled.');
      } else {
        addLog('Notify not supported.');
      }

      setState(() {
        connected = true;
        connecting = false;
      });
    } catch (e) {
      try {
        await device?.disconnect();
      } catch (_) {}

      setState(() {
        connected = false;
        connecting = false;
      });

      addLog('Connection failed: $e');
    }
  }

  Future<void> sendText(String text) async {
    if (!connected || serialChar == null) {
      addLog('Not connected.');
      return;
    }

    if (text.isEmpty) {
      addLog('Nothing to send.');
      return;
    }

    if (!serialChar!.properties.write &&
        !serialChar!.properties.writeWithoutResponse) {
      addLog('Characteristic is not writable.');
      return;
    }

    try {
      await serialChar!.write(
        text.codeUnits,
        withoutResponse: serialChar!.properties.writeWithoutResponse,
      );

      addLog('TX: $text');
    } catch (e) {
      addLog('Send failed: $e');
    }
  }

  Future<void> readData() async {
    if (!connected || serialChar == null) {
      addLog('Not connected.');
      return;
    }

    if (!serialChar!.properties.read) {
      addLog('Read not supported.');
      return;
    }

    try {
      final value = await serialChar!.read();
      final text = String.fromCharCodes(value);
      addLog('READ: $text');
    } catch (e) {
      addLog('Read failed: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await notifySub?.cancel();
      notifySub = null;
    } catch (_) {}

    try {
      await device?.disconnect();
    } catch (_) {}

    if (mounted) {
      setState(() {
        connected = false;
        connecting = false;
      });
    }
  }

  Future<void> reconnect() async {
    await disconnect();
    await connectBleSerial();
  }

  @override
  Widget build(BuildContext context) {
    final statusIcon = connected ? Icons.check_circle : Icons.error;
    final statusColor = connected ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Serial HC-05'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                widget.deviceName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                widget.deviceId,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(statusIcon, color: statusColor),
                  const SizedBox(width: 8),
                  Text(
                    connecting
                        ? 'Connecting...'
                        : connected
                        ? 'Connected'
                        : 'Disconnected',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: connected ? () => sendText('1') : null,
                      child: const Text('Send 1 / ON'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: connected ? () => sendText('0') : null,
                      child: const Text('Send 0 / OFF'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Custom message',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: connected
                        ? () => sendText(messageController.text)
                        : null,
                    child: const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: connected ? readData : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Read'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: connecting ? null : reconnect,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      logText,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}