import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'mqtt_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const MyAppWrapper());
}

class MyAppWrapper extends StatelessWidget {
  const MyAppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Garden HUSC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F6),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('vi')],
      home: const MyApp(),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final mqtt = MQTTService();

  bool isConnected = false;
  bool isAuto = false;
  bool isRepeat = false;
  TimeOfDay? selectedTime;
  bool isTimeLocked = true;

  String temp = "--";
  String hum = "--";
  String? activeZone;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => initMQTT());
  }

  // ================= LOGIC MQTT =================
  Future<void> initMQTT() async {
    try {
      await mqtt.connect();
    } catch (e) {
      debugPrint("MQTT lỗi: $e");
      return;
    }

    if (!mounted) return;

    if (mqtt.isConnected()) {
      setState(() => isConnected = true);

      // Nhận dữ liệu thời tiết
      mqtt.subscribe("weather", (msg) {
        if (msg == "off2") {
          if (mounted) setState(() => activeZone = null);
          return;
        }
        final parts = msg.split(",");
        if (parts.length == 2 && mounted) {
          setState(() {
            temp = parts[0];
            hum = parts[1];
          });
        }
      });

      // Nhận phản hồi trạng thái từ ESP8266
      mqtt.subscribe("control", (msg) {
        if (!mounted) return;
        
        if (msg == "off2") {
          setState(() {
            activeZone = null;
            if (!isRepeat) {
              isAuto = false;
              isTimeLocked = true;
            }
          });
          return;
        }

        if (msg.startsWith("STATE")) {
          final parts = msg.split("|");
          final t = parts[2].split(":");
          final h = int.parse(t[0]);
          final m = int.parse(t[1]);

          setState(() {
            isAuto = parts[1] == "1";
            if (!(h == 0 && m == 0)) {
              selectedTime = TimeOfDay(hour: h, minute: m);
            }
            isRepeat = parts[3] == "1";
            isTimeLocked = isAuto;
          });
        }
      });

      // Yêu cầu cập nhật thông số ngay khi vừa kết nối
      Future.delayed(const Duration(milliseconds: 1000), () {
        mqtt.publish("control", "readWeather");
        mqtt.publish("control", "GET_STATE");
      });
    }
  }

  void sendAuto() {
    if (!isConnected || selectedTime == null) return;
    final timeStr = "${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}";
    final msg = "AUTO|${isAuto ? 1 : 0}|$timeStr|${isRepeat ? 1 : 0}";
    mqtt.publish("control", msg);
  }

  void pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
    );

    if (time != null && mounted) {
      setState(() {
        selectedTime = time;
        isTimeLocked = true;
      });
      sendAuto();
    }
  }

  void handleManual(String value) {
    if (!mqtt.isConnected()) return;
    setState(() => activeZone = value);
    mqtt.publish("control", value);
  }

  // ================= UI BUILDERS =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            Image.asset(
              'assets/logo_husc.png', // Sử dụng logo đã giải quyết xong
              height: 40,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.school, color: Colors.green),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Smart Garden", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                Text("HUSC - Đại học Khoa học Huế", style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatusHeader(),
            const SizedBox(height: 16),
            _buildWeatherCard(),
            const SizedBox(height: 16),
            _buildManualControlCard(),
            const SizedBox(height: 16),
            _buildAutoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isConnected ? Icons.check_circle : Icons.error, color: isConnected ? Colors.green : Colors.red, size: 16),
          const SizedBox(width: 8),
          Text(isConnected ? "Đã kết nối hệ thống" : "Mất kết nối MQTT", 
              style: TextStyle(color: isConnected ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildWeatherCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildGauge("Nhiệt độ", temp, 60, Colors.redAccent, "°C"),
            _buildGauge("Độ ẩm", hum, 100, Colors.blueAccent, "%"),
          ],
        ),
      ),
    );
  }

  Widget _buildGauge(String title, String val, double max, Color color, String unit) {
    double value = double.tryParse(val) ?? 0;
    return Expanded(
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          SizedBox(
            height: 120,
            child: SfRadialGauge(
              axes: [
                RadialAxis(
                  minimum: 0, maximum: max, showLabels: false, showTicks: false,
                  axisLineStyle: const AxisLineStyle(thickness: 10, cornerStyle: CornerStyle.bothCurve),
                  pointers: [RangePointer(value: value, width: 10, color: color, cornerStyle: CornerStyle.bothCurve)],
                  annotations: [
                    GaugeAnnotation(
                      widget: Text("$val$unit", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      angle: 90, positionFactor: 0.1,
                    )
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualControlCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text("Điều khiển bơm", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: ["0", "1", "2", "3", "4"].map((z) => _buildZoneButton(z)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneButton(String zone) {
    bool isActive = activeZone == zone;
    String label = zone == "0" ? "Tất cả" : "Vùng $zone";

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.blueAccent : Colors.grey.shade100,
        foregroundColor: isActive ? Colors.white : Colors.black87,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: !isConnected ? null : () {
        if (isActive) {
          setState(() => activeZone = null);
          mqtt.publish("control", "off");
        } else {
          handleManual(zone);
        }
      },
      child: Text(isActive ? "Tắt" : label),
    );
  }

  Widget _buildAutoCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text("Tưới tự động", style: TextStyle(fontWeight: FontWeight.bold)),
            value: isAuto,
            onChanged: !isConnected ? null : (v) {
              setState(() {
                isAuto = v;
                isTimeLocked = !v;
              });
              sendAuto();
            },
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: Text(selectedTime == null ? "Chưa chọn giờ" : "Giờ tưới: ${selectedTime!.format(context)}"),
            trailing: TextButton(
              onPressed: isAuto ? pickTime : null,
              child: const Text("Chọn giờ"),
            ),
          ),
          CheckboxListTile(
            title: const Text("Lặp lại hàng ngày"),
            value: isRepeat,
            onChanged: isAuto ? (v) => setState(() { isRepeat = v!; sendAuto(); }) : null,
          ),
        ],
      ),
    );
  }
}