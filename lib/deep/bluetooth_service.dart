import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothDeviceManager {
  static final BluetoothDeviceManager _instance = BluetoothDeviceManager._internal();
  factory BluetoothDeviceManager() => _instance;
  BluetoothDeviceManager._internal();

  // 设备UUID配置 - 根据您的硬件设备修改
  final String serviceUUID = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String characteristicUUID = "0000ffe1-0000-1000-8000-00805f9b34fb";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _controlCharacteristic;

  // 获取已连接的设备
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // 获取控制特征
  BluetoothCharacteristic? get controlCharacteristic => _controlCharacteristic;

  // 检查并请求权限
  Future<bool> checkPermissions() async {
    if (await Permission.bluetoothConnect.request().isGranted && await Permission.bluetoothScan.request().isGranted && await Permission.location.request().isGranted) {
      return true;
    }
    return false;
  }

  // 检查蓝牙是否可用
  Future<bool> isBluetoothAvailable() async {
    return await FlutterBluePlus.isAvailable;
  }

  // 开启蓝牙
  Future<void> turnOnBluetooth() async {
    if (await FlutterBluePlus.isAvailable == false) {
      throw Exception("设备不支持蓝牙");
    }

    // 检查蓝牙适配器状态
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      await FlutterBluePlus.turnOn();
      // 等待蓝牙开启
      await FlutterBluePlus.adapterState.where((state) => state == BluetoothAdapterState.on).first;
    }
  }

  // 获取扫描结果流
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  // 获取扫描状态
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  // 开始扫描设备
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      await FlutterBluePlus.startScan(timeout: timeout, continuousUpdates: true);
    } catch (e) {
      debugPrint("扫描错误: $e");
      rethrow;
    }
  }

  // 停止扫描
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint("停止扫描错误: $e");
    }
  }

  // 连接设备
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      // 设置连接超时
      await device.connect(license: License.free,timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      // 监听连接状态
      device.connectionState.listen((state) {
        debugPrint("连接状态: $state");
        if (state == BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          _controlCharacteristic = null;
        }
      });

      // 发现服务
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid.toString() == serviceUUID) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == characteristicUUID) {
              _controlCharacteristic = characteristic;
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint("连接失败: $e");
      return false;
    }
  }

  // 断开连接
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _controlCharacteristic = null;
    }
  }

  // 发送控制命令到设备
  Future<void> sendCommand(List<int> command) async {
    if (_controlCharacteristic == null) {
      throw Exception("未找到控制特征或设备未连接");
    }

    try {
      await _controlCharacteristic!.write(command);
      debugPrint("命令发送成功: $command");
     
    } catch (e) {
      debugPrint("命令发送失败: $e");
      rethrow;
    }
  }

  // 监听设备返回的数据
  Stream<List<int>> get onDataReceived {
    if (_controlCharacteristic != null) {
      // 启用通知
      _controlCharacteristic!.setNotifyValue(true);
      return _controlCharacteristic!.onValueReceived;
    }
    return const Stream.empty();
  }

  // 获取连接状态流
  Stream<BluetoothConnectionState> get connectionState {
    if (_connectedDevice != null) {
      return _connectedDevice!.connectionState;
    }
    return Stream.value(BluetoothConnectionState.disconnected);
  }

  // 请求更大的MTU（传输单元）
  Future<int> requestMtu(int desiredMtu) async {
    if (_connectedDevice != null) {
      return await _connectedDevice!.requestMtu(desiredMtu);
    }
    throw Exception("设备未连接");
  }
}
