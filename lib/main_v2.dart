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
  
  // Biến vùng tưới thủ công (null nghĩa là đang tắt)
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
    await mqtt.connect(); 
    mqtt.subscribe("weather", (message) {
      if (message == "on2") {
        _addLog("Hệ thống bơm đang hoạt động");
      } else if (message == "off2") {
        setState(() => activeZone = null);
        _addLog("Bơm đã TẮT");
      } else if (message.contains("|")) {
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
      _addLog("Hẹn giờ: $timeStr ($wateringDuration phút)");
    } else {
      _addLog("Đã hủy hẹn giờ tự động");
    }
  }

  void _handleManual(String zone) {
    setState(() => activeZone = zone);
    mqtt.publish("control", zone);
    String zoneName = zone == "0" ? "Tất cả vùng" : "Vùng $zone";
    _addLog("Bật thủ công: $zoneName");
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
            // 1. Đồng hồ đo
            Row(
              children: [
                Expanded(child: _buildGauge("Nhiệt độ", temp, 50, Colors.redAccent, "°C", Icons.thermostat)),
                const SizedBox(width: 10),
                Expanded(child: _buildGauge("Độ ẩm", humid, 100, Colors.blueAccent, "%", Icons.water_drop)),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Biểu đồ thay đổi
            _buildChartSection(),
            const SizedBox(height: 16),

            // 3. Điều khiển thủ công (Vùng tưới)
            _buildCard(
              title: "Tưới thủ công ngay bây giờ",
              icon: Icons.touch_app,
              color: Colors.green,
              child: Wrap(
                spacing: 12, runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildZoneButton("1"), _buildZoneButton("2"),
                  _buildZoneButton("3"), _buildZoneButton("4"),
                  _buildZoneButton("0", isAll: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4. Hẹn giờ tự động
            _buildCard(
              title: "Hẹn giờ tưới",
              icon: Icons.alarm,
              color: Colors.purple,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text("Kích hoạt tự động", style: TextStyle(fontWeight: FontWeight.w500)),
                    value: isAuto,
                    activeThumbColor: Colors.purple,
                    onChanged: (val) {
                      setState(() => isAuto = val);
                      _sendAutoCommand();
                    },
                  ),
                  ListTile(
                    title: const Text("Giờ bắt đầu tưới"),
                    trailing: Text(
                      selectedTime?.format(context) ?? "Chưa chọn",
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
                      children: [
                        Text("Tưới trong: $wateringDuration phút", style: const TextStyle(fontWeight: FontWeight.w600)),
                        Slider(
                          value: wateringDuration.toDouble(),
                          min: 1, max: 30, divisions: 29,
                          label: "$wateringDuration phút",
                          activeColor: Colors.purple,
                          onChanged: (val) => setState(() => wateringDuration = val.toInt()),
                          onChangeEnd: (val) { if (isAuto) _sendAutoCommand(); },
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text("Lặp lại hằng ngày"),
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

            // 5. Nhật ký
            _buildCard(
              title: "Nhật ký chăm sóc",
              icon: Icons.history,
              color: Colors.teal,
              child: logs.isEmpty 
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("Chưa có hoạt động", style: TextStyle(color: Colors.grey))))
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

  // --- WIDGET COMPONENTS ---

  Widget _buildZoneButton(String zone, {bool isAll = false}) {
    bool isActive = activeZone == zone;
    String label = isAll ? "TẤT CẢ VÙNG" : "VÙNG $zone";
    return InkWell(
      onTap: () {
        if (isActive) {
          setState(() => activeZone = null);
          mqtt.publish("control", "off");
          _addLog("Đã tắt máy bơm");
        } else {
          _handleManual(zone);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: isAll ? double.infinity : (MediaQuery.of(context).size.width - 60) / 2,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? Colors.blueAccent : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? Colors.blueAccent : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(isActive ? Icons.water_drop : Icons.water_drop_outlined, color: isActive ? Colors.white : Colors.blueGrey),
            const SizedBox(height: 8),
            Text(isActive ? "ĐANG TƯỚI..." : label, style: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
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
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 4), Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey))],
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
            name: 'Nhiệt độ', dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.time, yValueMapper: (ChartData data, _) => data.temp,
            color: Colors.redAccent, width: 3,
          ),
          SplineSeries<ChartData, DateTime>(
            name: 'Độ ẩm', dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.time, yValueMapper: (ChartData data, _) => data.humid,
            color: Colors.blueAccent, width: 3,
          ),
        ],
      ),
    );
  }
}