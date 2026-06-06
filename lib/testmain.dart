import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LedTestScreen(),
  ));
}

class LedTestScreen extends StatefulWidget {
  const LedTestScreen({super.key});

  @override
  State<LedTestScreen> createState() => _LedTestScreenState();
}

class _LedTestScreenState extends State<LedTestScreen> {
  late MqttServerClient client;
  bool isConnected = false;
  bool isLedOn = false;

  @override
  void initState() {
    super.initState();
    _connectMQTT();
  }

  Future<void> _connectMQTT() async {
    // Tạo Client ID ngẫu nhiên cho điện thoại
    final clientId = 'flutter_phone_${DateTime.now().millisecondsSinceEpoch}';
    
    client = MqttServerClient.withPort(
      '39d12a87b87b47f099d56965c5453701.s1.eu.hivemq.cloud',
      clientId,
      8883,
    );
    client.secure = true;
    client.keepAlivePeriod = 20;

    final connMess = MqttConnectMessage()
        .authenticateAs('garden', 'Husc2026')
        .withClientIdentifier(clientId)
        .startClean();
    client.connectionMessage = connMess;

    try {
      print('Đang kết nối HiveMQ...');
      await client.connect();
      setState(() => isConnected = true);
      print('Kết nối thành công!');
    } catch (e) {
      print('Lỗi kết nối: $e');
      client.disconnect();
    }
  }

  void _sendControl(String command) {
    if (!isConnected) return;
    
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    
    // Gửi lệnh vào đúng topic mà ESP8266 đang lắng nghe
    client.publishMessage('test/led', MqttQos.atLeastOnce, builder.payload!);
    
    setState(() {
      isLedOn = (command == "on");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Test Điều Khiển Từ Xa"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isLedOn ? Icons.lightbulb : Icons.lightbulb_outline,
              size: 150,
              color: isLedOn ? Colors.orange : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              isConnected ? "Trạng thái: Đã kết nối Máy Chủ" : "Trạng thái: Đang kết nối...",
              style: TextStyle(
                color: isConnected ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                  onPressed: () => _sendControl("on"),
                  child: const Text("BẬT ĐÈN", style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                  onPressed: () => _sendControl("off"),
                  child: const Text("TẮT ĐÈN", style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}