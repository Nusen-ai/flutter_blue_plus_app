import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothScanPage extends StatefulWidget {
  const BluetoothScanPage({super.key});

  @override
  State<BluetoothScanPage> createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage> {
  List<BluetoothDevice> _scannedDevices = []; // 扫描到的设备列表（去重）
  bool _isScanning = false; // 扫描状态
  BluetoothAdapterState _bleState = BluetoothAdapterState.unknown; // 蓝牙状态
  // BluetoothState _bleState = BluetoothState.unknown; // 蓝牙状态

  // 流订阅器（管理静态流的订阅与取消）
  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;
  // StreamSubscription<BluetoothState>? _stateSubscription;
  StreamSubscription<bool>? _scanStatusSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  @override
  void initState() {
    super.initState();
    // 1. 监听蓝牙状态（静态流）
    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      setState(() => _bleState = state);
      // 蓝牙关闭时自动停止扫描
      if (state == BluetoothAdapterState.off) {
        _stopScan();
      }
    });
    // _stateSubscription = FlutterBluePlus.state.listen((state) {
    //   setState(() => _bleState = state);
    //   // 蓝牙关闭时自动停止扫描
    //   if (state == BluetoothState.off) {
    //     _stopScan();
    //   }
    // });

    // 2. 监听扫描状态（静态流）
    _scanStatusSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      setState(() => _isScanning = isScanning);
    });

    // 3. 初始化：申请蓝牙权限
    _requestBluetoothPermissions();
  }

  /// 申请蓝牙相关权限（动态权限）
  Future<void> _requestBluetoothPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Android 11及以下扫描必需
    ].request();

    // 权限被拒时提示用户
    if (statuses[Permission.bluetoothScan] != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('蓝牙扫描权限被拒绝，无法扫描设备')));
      }
    }
  }

  /// 启动扫描（核心：静态方法调用）
  Future<void> _startScan() async {
    // 前置条件校验
    if (_bleState != BluetoothAdapterState.on) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('蓝牙未开启，请先开启蓝牙')));
      // 自动尝试开启蓝牙（静态方法）
      await FlutterBluePlus.turnOn();
      return;
    }

    if (_isScanning) return; // 避免重复扫描

    debugPrint('👏🏻清除前设备数量：${_scannedDevices.length}');

    // 清空历史设备列表
    setState(() => _scannedDevices = []);
    debugPrint('🌹清除后设备数量：${_scannedDevices.length}');

    try {
      // 启动扫描（静态方法，支持超时/过滤）
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20), // 扫描超时（必设）
        // 可选：过滤特定服务UUID的设备（只扫描包含目标服务的设备）
        // withServices: [Guid("0000ffe0-0000-1000-8000-00805f9b34fb")],
        // allowDuplicates: false, // 禁止重复设备（默认false）
      );

      // 监听扫描结果（静态流，核心）
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          // 设备去重：避免同一设备重复添加
          if (!_scannedDevices.contains(result.device)) {
            setState(() => _scannedDevices.add(result.device));
          }
          // 调试：打印设备信息
          debugPrint(
            '设备名称：${result.device.platformName.isEmpty ? "未知设备" : result.device.platformName} '
            '设备ID：${result.device.remoteId} '
            '信号强度：未知dBm',
            // '设备名称：${result.device.name.isEmpty ? "未知设备" : result.device.name} '
            // '设备ID：${result.device.id} '
            // '信号强度：${result.rssi}dBm',
          );
        }
      });
    } catch (e) {
      // 捕获扫描异常（如权限不足、蓝牙未开启）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('扫描异常：$e')));
      }
    }
  }

  /// 停止扫描（核心：静态方法调用）
  Future<void> _stopScan() async {
    if (_isScanning) {
      await FlutterBluePlus.stopScan();
    }
    // 取消扫描结果订阅（避免内存泄漏）
    _scanResultsSubscription?.cancel();
  }

  @override
  void dispose() {
    // 页面销毁时：停止扫描 + 取消所有流订阅
    _stopScan();
    _adapterStateStateSubscription.cancel();
    _scanStatusSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlutterBluePlus 静态扫描'),
        actions: [Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('蓝牙状态：${_bleState.name}'))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 扫描/停止按钮
            ElevatedButton(
              onPressed: _isScanning ? _stopScan : _startScan,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: Text(_isScanning ? '停止扫描' : '开始扫描', style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 20),
            // 扫描状态提示
            Text(_isScanning ? '正在扫描BLE设备...' : '扫描已停止', style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 20),
            // 扫描结果列表
            Expanded(
              child: _scannedDevices.isEmpty
                  ? const Center(child: Text('未扫描到设备，请点击开始扫描', style: TextStyle(fontSize: 16)))
                  : ListView.builder(
                      itemCount: _scannedDevices.length,
                      itemBuilder: (context, index) {
                        BluetoothDevice device = _scannedDevices[index];
                        return ListTile(
                          title: Text(device.platformName.isEmpty ? '未知设备' : device.platformName),
                          subtitle: Text('设备ID: ${device.remoteId}'),
                          trailing: Text('信号: ${device.mtuNow}dBm'), // TODO: 需核实

                          // trailing: Text('信号：${device.rssi}dBm'),
                          onTap: () {
                            // 点击设备可执行连接操作（后续用静态方法实现）
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选中设备：${device.name.isEmpty ? "未知设备" : device.name}')));
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
