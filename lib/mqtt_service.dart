import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService {
  MqttServerClient? client;

  Future<void> connect() async {
    client = MqttServerClient(
      '39d12a87b87b47f099d56965c5453701.s1.eu.hivemq.cloud',  //Dien url MQTT cua Nguyen vao day
      'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
    );

    client!.port = 8883;
    client!.secure = true;
    client!.keepAlivePeriod = 60;
    client!.logging(on: true);
    client!.autoReconnect = true;

    //client.secure = true;
    //client.port = 8883;
    client!.setProtocolV311();
    //client!.securityContext = null;

    

    try {
      await client!.connect('garden', 'Husc2026'); //Dien user va pass MQTT client cua Nguyen vao day

      


      print("MQTT connected");
    } catch (e) {
      print("MQTT error: $e");
      client!.disconnect();
    }
  }

  bool isConnected() {
    return client?.connectionStatus?.state ==
        MqttConnectionState.connected;
  }

  void publish(String topic, String message) {
    if (client == null) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    client!.publishMessage(
        topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void subscribe(String topic, Function(String) onMessage) {
    if (client == null) return;

    client!.subscribe(topic, MqttQos.atLeastOnce);

    client!.updates!.listen((events) {
      final recMess = events[0].payload as MqttPublishMessage;
      final msg =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      onMessage(msg);
    });
  }
}