import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_app/deep/bluetooth_service.dart';

class BluetoothControllerApp extends StatefulWidget {
  const BluetoothControllerApp({super.key});
  @override
  State<BluetoothControllerApp> createState() => _BluetoothControllerAppState();
}

class _BluetoothControllerAppState extends State<BluetoothControllerApp> {
  final BluetoothDeviceManager bluetoothManager = BluetoothDeviceManager();
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isConnected = false;
  String connectionStatus = "未连接";

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  void _initializeBluetooth() async {
    // 监听扫描结果
    bluetoothManager.scanResults.listen((results) {
      setState(() {
        scanResults = results.where((result) => result.device.name.isNotEmpty).toList();
      });
    });

    // 监听扫描状态
    bluetoothManager.isScanning.listen((scanning) {
      setState(() {
        isScanning = scanning;
      });
    });

    // 监听连接状态
    bluetoothManager.connectionState.listen((state) {
      setState(() {
        isConnected = state == BluetoothConnectionState.connected;
        connectionStatus = _getConnectionStatusText(state);
      });
    });

    // 监听设备返回的数据
    bluetoothManager.onDataReceived.listen((data) {
      debugPrint("收到设备数据: $data");
      // 处理设备返回的数据
    });
  }

  String _getConnectionStatusText(BluetoothConnectionState state) {
    switch (state) {
      case BluetoothConnectionState.connected:
        return "已连接";
      case BluetoothConnectionState.connecting:
        return "连接中";
      case BluetoothConnectionState.disconnected:
        return "未连接";
      case BluetoothConnectionState.disconnecting:
        return "断开中";
    }
  }

  Future<void> _startBluetoothScan() async {
    // 检查权限
    bool hasPermission = await bluetoothManager.checkPermissions();
    if (!hasPermission) {
      _showErrorDialog("需要蓝牙和位置权限才能扫描设备");
      return;
    }

    // 开启蓝牙
    try {
      await bluetoothManager.turnOnBluetooth();
    } catch (e) {
      _showErrorDialog("蓝牙开启失败: $e");
      return;
    }

    // 开始扫描
    try {
      await bluetoothManager.startScan();
    } catch (e) {
      _showErrorDialog("扫描失败: $e");
    }
  }

  void _stopBluetoothScan() {
    bluetoothManager.stopScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    bool success = await bluetoothManager.connectToDevice(device);
    if (success) {
      _showSuccessDialog("设备连接成功");

      // 请求更大的MTU以提高数据传输效率
      try {
        await bluetoothManager.requestMtu(512);
        debugPrint("MTU请求成功");
      } catch (e) {
        debugPrint("MTU请求失败: $e");
      }
    } else {
      _showErrorDialog("设备连接失败，请检查服务UUID配置");
    }
  }

  void _disconnectDevice() {
    bluetoothManager.disconnect();
  }

  // 设备控制方法 - 根据您的硬件协议修改命令值
  void _sendControlCommand(int command) {
    bluetoothManager.sendCommand([command]);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("错误"),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("确定"))],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("成功"),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("确定"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('蓝牙设备控制器'),
        backgroundColor: Colors.blue,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                connectionStatus,
                style: TextStyle(color: isConnected ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 控制面板
          if (isConnected) _buildControlPanel(),

          // 扫描控制区域
          _buildScanControlPanel(),

          // 设备列表
          Expanded(child: _buildDeviceList()),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      margin: EdgeInsets.all(16.0),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('设备控制面板', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(onPressed: () => _sendControlCommand(0x01), child: Text('开启设备')),
                ElevatedButton(onPressed: () => _sendControlCommand(0x02), child: Text('关闭设备')),
                ElevatedButton(onPressed: () => _sendControlCommand(0x03), child: Text('模式一')),
                ElevatedButton(onPressed: () => _sendControlCommand(0x04), child: Text('模式二')),
                ElevatedButton(onPressed: () => _sendControlCommand(0x05), child: Text('模式三')),
              ],
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _disconnectDevice,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text('断开连接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanControlPanel() {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(onPressed: isScanning ? null : _startBluetoothScan, icon: Icon(Icons.search), label: Text('开始扫描')),
              ),
              SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isScanning ? _stopBluetoothScan : null,
                  icon: Icon(Icons.stop),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  label: Text('停止扫描'),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          if (isScanning)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('扫描中...', style: TextStyle(color: Colors.blue)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (scanResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(isScanning ? '正在搜索设备...' : '点击"开始扫描"搜索设备', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: scanResults.length,
      itemBuilder: (context, index) {
        final device = scanResults[index].device;
        final rssi = scanResults[index].rssi;

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Icon(Icons.bluetooth, color: Colors.blue),
            title: Text(device.platformName.isNotEmpty ? device.platformName : '未知设备'),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('MAC: ${device.remoteId}'), Text('信号强度: $rssi dBm')]),
            trailing: ElevatedButton(onPressed: () => _connectToDevice(device), child: Text('连接')),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // 断开连接并停止扫描
    bluetoothManager.disconnect();
    bluetoothManager.stopScan();
    super.dispose();
  }
}
