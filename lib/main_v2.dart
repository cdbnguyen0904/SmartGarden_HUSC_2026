import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:syncfusion_flutter_charts/charts.dart' hide CornerStyle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'mqtt_service.dart';

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
        scaffoldBackgroundColor: const Color(0xFFF0F4F3),
      ),
      home: const MyApp(),
    );
  }
}

class ChartData {
  ChartData(this.time, this.temp, this.humid);
  final DateTime time;
  final double temp;
  final double humid;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // --- BIẾN TRẠNG THÁI ---
  double temp = 0.0;
  double humid = 0.0;
  bool isMqttConnected = false;
  String? activeZone;

  // Biến hẹn giờ
  bool isAuto = false;
  TimeOfDay? selectedTime;
  bool isRepeat = false;
  int wateringDuration = 5;

  List<String> logs = [];
  List<ChartData> chartData = [];

  final MQTTService mqtt = MQTTService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _setupMqtt();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isAuto = prefs.getBool('isAuto') ?? false;
      isRepeat = prefs.getBool('isRepeat') ?? false;
      wateringDuration = prefs.getInt('wateringDuration') ?? 5;
      
      final hour = prefs.getInt('autoHour');
      final minute = prefs.getInt('autoMinute');
      if (hour != null && minute != null) {
        selectedTime = TimeOfDay(hour: hour, minute: minute);
      }
      logs = prefs.getStringList('logs') ?? [];
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isAuto', isAuto);
    prefs.setBool('isRepeat', isRepeat);
    prefs.setInt('wateringDuration', wateringDuration);
    if (selectedTime != null) {
      prefs.setInt('autoHour', selectedTime!.hour);
      prefs.setInt('autoMinute', selectedTime!.minute);
    }
    prefs.setStringList('logs', logs);
  }

  void _setupMqtt() async {
    setState(() => isMqttConnected = false);
    try {
      await mqtt.connect(); 
      setState(() => isMqttConnected = true);
      
      mqtt.subscribe("weather", (message) {
        // 1. Nhận mã lệnh TẮT
        if (message == "off" || message == "off2") { 
          setState(() => activeZone = null);
          _addLog("All devices turned OFF");
        } 
        // 2. Nhận mã lệnh BẬT cụ thể
        else if (message.startsWith("on") && message.length == 3) {
          String zoneReceived = message.substring(2); 
          if (["0", "1", "2", "3", "4"].contains(zoneReceived)) {
            setState(() => activeZone = zoneReceived);
            String zoneName = zoneReceived == "0" ? "All Zones" : "Zone $zoneReceived";
            _addLog("Hardware status: $zoneName is RUNNING");
          }
        } 
        // 3. Nhận dữ liệu cảm biến
        else if (message.contains("|")) {
          var parts = message.split("|");
          if (parts.length >= 2) {
            setState(() {
              temp = double.tryParse(parts[0]) ?? temp;
              humid = double.tryParse(parts[1]) ?? humid;
              
              chartData.add(ChartData(DateTime.now(), temp, humid));
              if (chartData.length > 20) chartData.removeAt(0);
            });
          }
        }
      });
    } catch (e) {
      setState(() => isMqttConnected = false);
      _addLog("MQTT Broker connection failed");
    }
  }

  void _addLog(String log) {
    setState(() {
      final now = DateFormat('HH:mm').format(DateTime.now());
      logs.insert(0, "[$now] $log");
      if (logs.length > 10) logs.removeLast();
    });
    _saveSettings();
  }

  void _sendAutoCommand() {
    if (selectedTime == null) return;
    _saveSettings();
    final timeStr = "${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}";
    final msg = "AUTO|${isAuto ? 1 : 0}|$timeStr|${isRepeat ? 1 : 0}|$wateringDuration";
    mqtt.publish("control", msg);
    
    if (isAuto) {
      _addLog("Schedule enabled: $timeStr ($wateringDuration mins)");
    } else {
      _addLog("Schedule disabled");
    }
  }

  void _handleManual(String zone) {
    setState(() => activeZone = zone);
    mqtt.publish("control", zone);
    String zoneName = zone == "0" ? "All Zones" : "Zone $zone";
    _addLog("Command sent: Turn ON $zoneName");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        title: Row(
          children: [
            Image.asset(
              'assets/logo_husc.png',
              height: 40,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.school, color: Colors.green, size: 40),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Smart Garden", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                Text("Trường ĐH Khoa học Huế", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Trạng thái MQTT kết nối
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: isMqttConnected ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isMqttConnected ? Colors.green : Colors.red, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(
                    isMqttConnected ? Icons.cloud_done : Icons.cloud_off,
                    color: isMqttConnected ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isMqttConnected ? "Broker Server: Connected" : "Broker Server: Disconnected (Retrying...)",
                      style: TextStyle(
                        color: isMqttConnected ? Colors.green.shade900 : Colors.red.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Đồng hồ đo Gauges
            Row(
              children: [
                Expanded(child: _buildGauge("Temperature", temp, 50, Colors.redAccent, "°C", Icons.thermostat)),
                const SizedBox(width: 10),
                Expanded(child: _buildGauge("Humidity", humid, 100, Colors.blueAccent, "%", Icons.water_drop)),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Biểu đồ Spline Chart
            _buildChartSection(),
            const SizedBox(height: 16),

            // 4. KIỂM SOÁT THỦ CÔNG (ĐÃ FIX CHỐNG TRÀN OVERFLOW HOÀN HẢO)
            _buildCard(
              title: "Manual Control",
              icon: Icons.touch_app,
              color: Colors.green,
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.0, // Chỉnh xuống 2.0 để tăng chiều cao an toàn cho nút bấm
                children: [
                  _buildZoneButton("1"),
                  _buildZoneButton("2"),
                  _buildZoneButton("3"),
                  _buildZoneButton("4"),
                  _buildZoneButton("0"),   // Nút ALL ON
                  _buildZoneButton("off"), // Nút ALL OFF (Kill Switch) màu đỏ
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. Hẹn giờ tự động Auto Schedule
            _buildCard(
              title: "Auto Schedule",
              icon: Icons.alarm,
              color: Colors.purple,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text("Enable Automation", style: TextStyle(fontWeight: FontWeight.w500)),
                    value: isAuto,
                    activeThumbColor: Colors.purple,
                    onChanged: (val) {
                      setState(() => isAuto = val);
                      _sendAutoCommand();
                    },
                  ),
                  ListTile(
                    title: const Text("Start Time"),
                    trailing: Text(
                      selectedTime?.format(context) ?? "Not Set",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final time = await showTimePicker(context: context, initialTime: selectedTime ?? TimeOfDay.now());
                      if (time != null) {
                        setState(() => selectedTime = time);
                        if (isAuto) _sendAutoCommand();
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Duration: $wateringDuration mins", style: const TextStyle(fontWeight: FontWeight.w600)),
                        Slider(
                          value: wateringDuration.toDouble(),
                          min: 1, max: 30, divisions: 29,
                          label: "$wateringDuration mins",
                          activeColor: Colors.purple,
                          onChanged: (val) => setState(() => wateringDuration = val.toInt()),
                          onChangeEnd: (val) { if (isAuto) _sendAutoCommand(); },
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text("Daily Repeat"),
                    value: isRepeat,
                    activeThumbColor: Colors.purple,
                    onChanged: (val) {
                      setState(() => isRepeat = val);
                      if (isAuto) _sendAutoCommand();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. NHẬT KÝ HOẠT ĐỘNG (100% TIẾNG ANH)
            _buildCard(
              title: "Activity Log",
              icon: Icons.history,
              color: Colors.teal,
              child: logs.isEmpty 
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text("No activities recorded yet.", style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: logs.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_circle, color: Colors.teal, size: 20),
                        title: Text(logs[index]),
                      ),
                    ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- HÀM TẠO NÚT BẤM (ĐÃ BỌC FITTEDBOX & FLEXIBLE TUYỆT ĐỐI KHÔNG OVERFLOW) ---
  Widget _buildZoneButton(String zone) {
    bool isActive;
    String label;
    IconData icon;
    Color activeColor;

    if (zone == "off") {
      isActive = (activeZone == null); 
      label = "ALL OFF";
      icon = Icons.power_settings_new;
      activeColor = Colors.redAccent;
    } else if (zone == "0") {
      isActive = (activeZone == "0");
      label = "ALL ON";
      icon = Icons.bolt;
      activeColor = Colors.blueAccent;
    } else {
      isActive = (activeZone == zone);
      label = "ZONE $zone";
      icon = Icons.water_drop;
      activeColor = Colors.blueAccent;
    }

    return InkWell(
      onTap: () {
        if (zone == "off") {
          setState(() => activeZone = null);
          mqtt.publish("control", "off");
          _addLog("Emergency stop activated: ALL OFF");
        } else {
          if (isActive) {
            setState(() => activeZone = null);
            mqtt.publish("control", "off");
            _addLog("Command sent: Turn OFF all zones");
          } else {
            _handleManual(zone);
          }
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 6), // Thu hẹp padding dọc tối ưu khoảng trống
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? activeColor : Colors.grey.shade300, width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // Ép Column co cụm theo nội dung
          children: [
            Icon(
              isActive ? icon : Icons.radio_button_unchecked, 
              color: isActive ? Colors.white : Colors.blueGrey,
              size: 20, // Giảm nhẹ size icon để lấy không gian cho Text
            ),
            const SizedBox(height: 4),
            // Tấm khiên bảo vệ tối thượng: Giúp chữ tự thu nhỏ lại nếu màn hình Emulator quá hẹp
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  (isActive && zone != "off") ? "RUNNING..." : label, 
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.black87, 
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Color color, required Widget child}) {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildGauge(String title, double value, double max, Color color, String unit, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.grey), 
              const SizedBox(width: 4), 
              Flexible(
                child: Text(
                  title, 
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 110,
            child: SfRadialGauge(
              axes: [
                RadialAxis(
                  minimum: 0, maximum: max, showLabels: false, showTicks: false,
                  axisLineStyle: const AxisLineStyle(thickness: 10, cornerStyle: CornerStyle.bothCurve),
                  pointers: [RangePointer(value: value, width: 10, color: color, cornerStyle: CornerStyle.bothCurve)],
                  annotations: [
                    GaugeAnnotation(
                      widget: Text("${value.toStringAsFixed(1)}$unit", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _buildChartSection() {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: SfCartesianChart(
        primaryXAxis: DateTimeAxis(dateFormat: DateFormat('HH:mm:ss'), majorGridLines: const MajorGridLines(width: 0)),
        primaryYAxis: NumericAxis(axisLine: const AxisLine(width: 0), majorTickLines: const MajorTickLines(size: 0)),
        legend: Legend(isVisible: true, position: LegendPosition.top),
        series: <CartesianSeries>[
          SplineSeries<ChartData, DateTime>(
            name: 'Temperature', dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.time, yValueMapper: (ChartData data, _) => data.temp,
            color: Colors.redAccent, width: 3,
          ),
          SplineSeries<ChartData, DateTime>(
            name: 'Humidity', dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.time, yValueMapper: (ChartData data, _) => data.humid,
            color: Colors.blueAccent, width: 3,
          ),
        ],
      ),
    );
  }
}
