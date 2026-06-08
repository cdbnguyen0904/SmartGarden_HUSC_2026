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
    oled.text("Initializing...", 0, 0)
    oled.show()
except Exception as e:
    print("Không tìm thấy OLED:", e)
    oled = None

# Hàm cập nhật Màn hình OLED (ĐÃ THÊM GIỜ VÀ TRẠNG THÁI)
def update_oled(t, h, gas, time_str, wifi_ok, mqtt_ok):
    if oled:
        oled.fill(0)
        # Tạo chuỗi trạng thái (VD: 14:30 W:OK M:OK)
        w_status = "OK" if wifi_ok else "ER"
        m_status = "OK" if mqtt_ok else "ER"
        header = "{} W:{} M:{}".format(time_str, w_status, m_status)
        
        oled.text(header, 0, 0)
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

# --- BIẾN TRẠNG THÁI HẸN GIỜ & MẠNG ---
isAuto = False
auto_time = "00:00"
isRepeat = False
auto_duration = 5 

is_pump_running_auto = False
pump_start_time = 0

wlan = network.WLAN(network.STA_IF)
wifi_ok = False
mqtt_ok = False
client = None

def connect_wifi():
    global wifi_ok
    wlan.active(True)
    if not wlan.isconnected():
        print("Đang kết nối WiFi...")
        wlan.connect(WIFI_SSID, WIFI_PASS)
        # CHỐNG TREO: Chỉ thử kết nối trong 15 giây rồi thoát ra chạy tiếp
        for _ in range(15):
            if wlan.isconnected():
                break
            time.sleep(1)
            
    if wlan.isconnected():
        wifi_ok = True
        print("WiFi Connected!", wlan.ifconfig())
        try:
            ntptime.settime()
            print("Đã đồng bộ NTP")
        except:
            pass
    else:
        wifi_ok = False
        print("Lỗi: Không có kết nối WiFi (Chế độ Offline)")

def safe_publish(topic, msg):
    """Hàm gửi MQTT an toàn, không làm treo máy nếu rớt mạng"""
    global mqtt_ok
    if mqtt_ok and client:
        try:
            client.publish(topic, msg)
        except OSError:
            mqtt_ok = False # Đánh dấu lỗi để tự kết nối lại sau

def sub_cb(topic, msg):
    global isAuto, auto_time, isRepeat, auto_duration, is_pump_running_auto
    topic = topic.decode()
    msg = msg.decode()
    print("Nhận MQTT:", topic, msg)

    if topic == "control":
        if msg in ["0", "1", "2", "3", "4"]:
            pump.value(1) # Bật bơm
            is_pump_running_auto = False 
            safe_publish("weather", "on2")
        elif msg == "off":
            pump.value(0) # Tắt bơm
            is_pump_running_auto = False
            safe_publish("weather", "off2")
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
    global client, mqtt_ok
    print("Đang kết nối HiveMQ...")
    ssl_config = {'server_hostname': MQTT_BROKER}
    client = MQTTClient(
        CLIENT_ID, MQTT_BROKER, port=MQTT_PORT,
        user=MQTT_USER, password=MQTT_PASSWORD, 
        ssl=True, ssl_params=ssl_config
    )
    client.set_callback(sub_cb)
    client.connect()
    client.subscribe(b"control")
    mqtt_ok = True
    print("Kết nối MQTT thành công!")

# ================= CHƯƠNG TRÌNH CHÍNH =================
connect_wifi()

if wifi_ok:
    try:
        connect_mqtt()
    except Exception as e:
        print("Lỗi kết nối MQTT ban đầu:", e)
        mqtt_ok = False

last_sensor_read = time.ticks_ms()
last_reconnect_try = time.ticks_ms()

while True:
    try:
        current_str = get_current_time_str()
        current_sec = time.time()
        wifi_ok = wlan.isconnected() # Cập nhật trạng thái WiFi liên tục

        # --- AUTO RECONNECT (Kết nối lại ngầm, không làm gián đoạn hẹn giờ) ---
        if wifi_ok and not mqtt_ok:
            if time.ticks_diff(time.ticks_ms(), last_reconnect_try) > 10000: # Cứ 10s thử 1 lần
                print("Đang thử khôi phục kết nối MQTT...")
                try:
                    connect_mqtt()
                except Exception as e:
                    print("Khôi phục MQTT thất bại:", e)
                last_reconnect_try = time.ticks_ms()

        # --- LẮNG NGHE MQTT ---
        if mqtt_ok:
            try:
                client.check_msg()
            except OSError:
                mqtt_ok = False # Rớt mạng, chuyển cờ để thử lại ở chu kỳ sau

        # === LOGIC HẸN GIỜ (Hoàn toàn độc lập, chạy cả khi Offline) ===
        if isAuto and current_str == auto_time and not is_pump_running_auto:
            pump.value(1)
            is_pump_running_auto = True
            pump_start_time = current_sec
            safe_publish("weather", "on2")
            print("Bắt đầu tự động tưới.")

        if is_pump_running_auto:
            elapsed_seconds = current_sec - pump_start_time
            if elapsed_seconds >= (auto_duration * 60):
                pump.value(0) 
                is_pump_running_auto = False
                safe_publish("weather", "off2")
                if not isRepeat:
                    isAuto = False

        # === ĐỌC CẢM BIẾN & CẬP NHẬT OLED ===
        if time.ticks_diff(time.ticks_ms(), last_sensor_read) > 5000:
            try:
                sensor_dht.measure()
                t = sensor_dht.temperature()
                h = sensor_dht.humidity()
                gas = gas_analog.read()
                
                # Cập nhật OLED hiển thị Giờ và Trạng thái mạng
                update_oled(t, h, gas, current_str, wifi_ok, mqtt_ok)
                
                # Gửi dữ liệu an toàn
                safe_publish("weather", "{}|{}".format(t, h))
            except Exception as e:
                print("Lỗi đọc cảm biến:", e)
                
            last_sensor_read = time.ticks_ms()
            
    except Exception as e:
        print("Lỗi vòng lặp:", e)      
        time.sleep(1)
        
    time.sleep(0.1)
