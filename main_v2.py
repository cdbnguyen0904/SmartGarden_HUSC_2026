import time
import machine
import dht
import network
import ntptime 
import ubinascii
from umqtt.simple import MQTTClient
from machine import Pin, SoftI2C, ADC
import sh1106

# --- CẤU HÌNH PHẦN CỨNG ---
PIN_PUMP = 2 # Chân kích relay (D4)
PIN_DHT = 0  # Chân DHT11 (D3)

pump = Pin(PIN_PUMP, Pin.OUT)
pump.value(0) 
sensor_dht = dht.DHT11(Pin(PIN_DHT))
gas_analog = ADC(0) # Cảm biến MQ gắn chân A0

# --- KHỞI TẠO OLED SH1106 ---
try:
    i2c = SoftI2C(scl=Pin(5), sda=Pin(4), freq=400000) # SCL: D1, SDA: D2
    oled = sh1106.SH1106_I2C(128, 64, i2c)
    oled.fill(0)
    oled.text("Initializing", 0, 0)
    oled.show()
except Exception as e:
    print("Không tìm thấy OLED:", e)
    oled = None

# Hàm cập nhật Màn hình OLED
def update_oled(t, h, gas):
    if oled:
        oled.fill(0)
        oled.text("Smart Garden", 15, 0)
        oled.text("Nhiet do: {} C".format(t), 0, 20)
        oled.text("Do am   : {} %".format(h), 0, 35)
        oled.text("Khi Gas : {}".format(gas), 0, 50)
        oled.show()

# --- CẤU HÌNH MẠNG & MQTT (HIVEMQ CLOUD) ---
WIFI_SSID = "iloveyou3000"
WIFI_PASS = "33333333"

MQTT_BROKER    = "39d12a87b87b47f099d56965c5453701.s1.eu.hivemq.cloud"
MQTT_USER      = b"garden"
MQTT_PASSWORD  = b"Husc2026"
MQTT_PORT      = 8883
CLIENT_ID      = ubinascii.hexlify(machine.unique_id())

# --- BIẾN TRẠNG THÁI HẸN GIỜ ---
isAuto = False
auto_time = "00:00"
isRepeat = False
auto_duration = 5 

is_pump_running_auto = False
pump_start_time = 0

def connect_wifi():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    if not wlan.isconnected():
        print("Đang kết nối WiFi...")
        wlan.connect(WIFI_SSID, WIFI_PASS)
        while not wlan.isconnected():
            time.sleep(1)
    print("WiFi Connected!", wlan.ifconfig())
    try:
        ntptime.settime()
        print("Đã đồng bộ NTP")
    except:
        pass

def sub_cb(topic, msg):
    global isAuto, auto_time, isRepeat, auto_duration, is_pump_running_auto
    topic = topic.decode()
    msg = msg.decode()
    print("Nhận MQTT:", topic, msg)

    if topic == "control":
        if msg in ["0", "1", "2", "3", "4"]:
            pump.value(1) # Bật bơm
            is_pump_running_auto = False 
            client.publish("weather", "on2")
        elif msg == "off":
            pump.value(0) # Tắt bơm
            is_pump_running_auto = False
            client.publish("weather", "off2")
        elif msg.startswith("AUTO"):
            parts = msg.split("|")
            isAuto = (parts[1] == "1")
            auto_time = parts[2]
            isRepeat = (parts[3] == "1")
            if len(parts) >= 5:
                auto_duration = int(parts[4])
            print("Cập nhật hẹn giờ: {} - {} phút".format(auto_time, auto_duration))

def get_current_time_str():
    t = time.localtime(time.time() + 7 * 3600)
    return "{:02d}:{:02d}".format(t[3], t[4])

def connect_mqtt():
    print("Đang kết nối HiveMQ...")
    ssl_config = {'server_hostname': MQTT_BROKER}
    mq_client = MQTTClient(
        CLIENT_ID, MQTT_BROKER, port=MQTT_PORT,
        user=MQTT_USER, password=MQTT_PASSWORD, 
        ssl=True, ssl_params=ssl_config
    )
    mq_client.set_callback(sub_cb)
    mq_client.connect()
    mq_client.subscribe(b"control")
    print("Kết nối MQTT thành công!")
    return mq_client

# ================= CHƯƠNG TRÌNH CHÍNH =================
connect_wifi()

try:
    client = connect_mqtt()
except Exception as e:
    print("Lỗi kết nối MQTT:", e)
    time.sleep(5)
    machine.reset()

last_sensor_read = time.ticks_ms()

while True:
    try:
        client.check_msg()
        current_str = get_current_time_str()
        current_sec = time.time()

        if isAuto and current_str == auto_time and not is_pump_running_auto:
            pump.value(1)
            is_pump_running_auto = True
            pump_start_time = current_sec
            client.publish("weather", "on2")
            print("Bắt đầu tự động tưới.")

        if is_pump_running_auto:
            elapsed_seconds = current_sec - pump_start_time
            if elapsed_seconds >= (auto_duration * 60):
                pump.value(0) 
                is_pump_running_auto = False
                client.publish("weather", "off2")
                if not isRepeat:
                    isAuto = False

        if time.ticks_diff(time.ticks_ms(), last_sensor_read) > 5000:
            try:
                sensor_dht.measure()
                t = sensor_dht.temperature()
                h = sensor_dht.humidity()
                gas = gas_analog.read()
                
                # Cập nhật OLED
                update_oled(t, h, gas)
                
                # Gửi lên App (Dùng dấu | phân cách)
                client.publish("weather", "{}|{}".format(t, h))
            except Exception as e:
                print("Lỗi đọc cảm biến:", e)
                
            last_sensor_read = time.ticks_ms()
            
    except Exception as e:
        print("Lỗi vòng lặp:", e)
        time.sleep(2)
        machine.reset()
        
    time.sleep(0.1)