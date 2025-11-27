import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
class BluetoothTestPage extends StatefulWidget {
  const BluetoothTestPage({super.key});

  @override
  State<BluetoothTestPage> createState() => _BluetoothTestPageState();
}

class _BluetoothTestPageState extends State<BluetoothTestPage> {
  final FlutterBluePlus _flutterBlue = FlutterBluePlus();
  List<BluetoothDevice> _scannedDevices = []; // 扫描到的设备列表
  BluetoothDevice? _connectedDevice; // 已连接的设备
  BluetoothCharacteristic? _targetChar; // 用于通信的特征（与模拟设备匹配）
  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;
  BluetoothAdapterState _bleState = BluetoothAdapterState.unknown; // 蓝牙状态
  // BluetoothState _bleState = BluetoothState.unknown; // 蓝牙状态
  String _feedbackData = "未收到设备反馈"; // 硬件/模拟设备的反馈数据

  @override
  void initState() {
    super.initState();
    // 监听蓝牙开关状态（2.0.2版本state为Stream<BluetoothState>）
    // _flutterBlue.state.listen((state) {
    //   setState(() => _bleState = state);
    // });
    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _bleState = state;
      if (mounted) {
        setState(() {});
      }
    });
    // 初始化蓝牙：申请权限 + 开启蓝牙
    _initBLE();
  }

  /// 初始化BLE蓝牙：申请权限 + 自动开启蓝牙
  Future<void> _initBLE() async {
    // 1. 动态申请权限（2.0.2版本需确保权限全部授予）
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Android 11及以下扫描需要
    ].request();

    // 检查权限是否通过
    if (statuses[Permission.bluetoothScan] != PermissionStatus.granted || statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('蓝牙权限申请失败，请手动开启！')));
      }
      return;
    }

    // 2. 开启蓝牙（如果未开启）
    if (_bleState != BluetoothAdapterState.on) {
      // await _flutterBlue.turnOn();
      await FlutterBluePlus.turnOn();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在开启蓝牙...')));
    }
  }

  /// 扫描BLE设备（2.0.2版本startScan参数与旧版一致）
  Future<void> _scanDevices() async {
    if (_bleState != BluetoothAdapterState.on) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('蓝牙未开启，无法扫描！')));
      return;
    }

    // 清空历史扫描结果
    setState(() => _scannedDevices = []);

    // 开始扫描（超时4秒，2.0.2版本支持设置扫描过滤）
    // _flutterBlue.startScan(timeout: const Duration(seconds: 4));
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

    // 监听扫描结果（2.0.2版本scanResults为Stream<List<ScanResult>>）
    // _flutterBlue.scanResults.listen((results) {
     FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (!_scannedDevices.contains(result.device)) {
          setState(() => _scannedDevices.add(result.device));
        }
      }
    });

    // 扫描结束提示
    // _flutterBlue.isScanning.listen((isScanning) {
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('扫描结束，共发现${_scannedDevices.length}台设备')));
      }
    });
  }

  /// 连接BLE设备（2.0.2版本connect方法稳定性优化）
  Future<void> _connectDevice(BluetoothDevice device) async {
    if (_connectedDevice != null) {
      await _disconnectDevice(_connectedDevice!);
    }

    try {
      // 连接设备（2.0.2版本支持设置连接超时）
      await device.connect(license: License.free,timeout: const Duration(seconds: 10));
      setState(() => _connectedDevice = device);

      // 发现设备的服务和特征（核心：与模拟设备的UUID匹配）
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        // 替换为**模拟设备的服务UUID**（示例：FFE0，需与nRF Connect配置一致）
        if (service.uuid.toString().toUpperCase().startsWith('FFE0')) {
          for (BluetoothCharacteristic char in service.characteristics) {
            // 替换为**模拟设备的特征UUID**（示例：FFE1，需与nRF Connect配置一致）
            if (char.uuid.toString().toUpperCase().startsWith('FFE1')) {
              setState(() => _targetChar = char);
              // 开启特征通知：监听模拟设备的反馈数据
              await char.setNotifyValue(true);
              // 监听特征值变化（接收模拟设备的反馈）
              char.value.listen((value) {
                setState(() {
                  _feedbackData = "收到反馈：${String.fromCharCodes(value)}";
                });
              });
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已连接设备：${device.name.isEmpty ? "未知设备" : device.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败：$e')));
      }
    }
  }

  /// 断开设备连接
  Future<void> _disconnectDevice(BluetoothDevice device) async {
    try {
      await device.disconnect();
      setState(() {
        _connectedDevice = null;
        _targetChar = null;
        _feedbackData = "未收到设备反馈";
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已断开连接')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('断开失败：$e')));
    }
  }

  /// 发送指令到模拟设备（2.0.2版本write方法支持两种写入模式）
  Future<void> _sendCommand(String command) async {
    if (_connectedDevice == null || _targetChar == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未连接设备或未找到通信特征！')));
      return;
    }

    // 检查特征是否支持写入（2.0.2版本properties属性与旧版一致）
    if (!_targetChar!.properties.write && !_targetChar!.properties.writeWithoutResponse) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该特征不支持写入指令！')));
      return;
    }

    try {
      // 将指令转为字节（与模拟设备的编码一致，默认UTF8）
      List<int> bytes = command.codeUnits;
      // 写入数据：writeWithoutResponse（无响应，速度快）/ write（带响应）
      await _targetChar!.write(bytes, withoutResponse: true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('指令发送成功：$command')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('指令发送失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE蓝牙测试（2.0.2）'), actions: [Text('蓝牙状态：${_bleState.name}'), const SizedBox(width: 10)]),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 扫描按钮
            ElevatedButton(onPressed: _scanDevices, child: const Text('扫描BLE设备')),
            const SizedBox(height: 20),
            // 扫描到的设备列表
            Expanded(
              flex: 2,
              child: _scannedDevices.isEmpty
                  ? const Center(child: Text('未扫描到设备，请点击扫描按钮'))
                  : ListView.builder(
                      itemCount: _scannedDevices.length,
                      itemBuilder: (context, index) {
                        BluetoothDevice device = _scannedDevices[index];
                        return ListTile(
                          title: Text(device.name.isEmpty ? "未知设备" : device.name),
                          subtitle: Text(device.id.toString()),
                          trailing: _connectedDevice == device ? const Icon(Icons.check, color: Colors.green) : ElevatedButton(onPressed: () => _connectDevice(device), child: const Text('连接')),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
            // 指令发送区（仅连接后显示）
            if (_connectedDevice != null)
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    Text('已连接：${_connectedDevice!.name.isEmpty ? "未知设备" : _connectedDevice!.name}'),
                    const SizedBox(height: 10),
                    // 指令输入框
                    TextField(
                      decoration: const InputDecoration(hintText: '输入指令（如open/close）', border: OutlineInputBorder()),
                      onSubmitted: _sendCommand, // 回车发送
                    ),
                    const SizedBox(height: 10),
                    // 快捷发送按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(onPressed: () => _sendCommand('open'), child: const Text('发送open')),
                        ElevatedButton(onPressed: () => _sendCommand('close'), child: const Text('发送close')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 设备反馈区
                    Text(_feedbackData, style: const TextStyle(color: Colors.red, fontSize: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _adapterStateStateSubscription.cancel();
    // 页面销毁时断开连接
    if (_connectedDevice != null) {
      _disconnectDevice(_connectedDevice!);
    }
    super.dispose();
  }
}
