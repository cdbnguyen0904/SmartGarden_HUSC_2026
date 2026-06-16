import time
import machine
import dht
import network
import ntptime 
import ubinascii
from umqtt.simple import MQTTClient
from machine import Pin, SoftI2C, ADC
import sh1106

# --- CẤU HÌNH PHẦN CỨNG (4 VÙNG) ---
PIN_DHT = 0  # Chân DHT11 (D3)
sensor_dht = dht.DHT11(Pin(PIN_DHT))
gas_analog = ADC(0) # Cảm biến MQ gắn chân A0

# Khởi tạo 4 thiết bị tương ứng 4 vùng
relay1 = Pin(15, Pin.OUT) # Vùng 1
relay2 = Pin(13, Pin.OUT) # Vùng 2
led1   = Pin(14, Pin.OUT) # Vùng 3
led2   = Pin(12, Pin.OUT) # Vùng 4

# Hàm điều khiển trạng thái 4 thiết bị cùng lúc
def set_devices(r1, r2, l1, l2):
    relay1.value(r1)
    relay2.value(r2)
    led1.value(l1)
    led2.value(l2)

# Tắt tất cả khi khởi động
set_devices(0, 0, 0, 0)

# --- KHỞI TẠO OLED SH1106 ---
try:
    i2c = SoftI2C(scl=Pin(5), sda=Pin(4), freq=400000) # SCL: D1, SDA: D2
    oled = sh1106.SH1106_I2C(128, 64, i2c)
    oled.fill(0)
    oled.text("--Smart Garden--", 0, 0)
    oled.text("Initializing...", 0, 16)
    oled.show()
except Exception as e:
    print("Không tìm thấy OLED:", e)
    oled = None

# --- HÀM CẬP NHẬT GIAO DIỆN OLED ---
def update_oled(t, h, gas, time_str, wifi_ok, mqtt_ok):
    if oled:
        oled.fill(0)
        
        # Dòng 1: Tên dự án
        oled.text("--Smart Garden--", 0, 0)
        
        # Dòng 2 & 3: Nhiệt độ, Độ ẩm viết tắt
        oled.text("Temp: {} C".format(t), 0, 16)
        oled.text("Hum : {} %".format(h), 0, 32)
        
        # Dòng 4: Thời gian và trạng thái mạng (W:OK/E, M:OK/E)
        w_status = "OK" if wifi_ok else "E"
        m_status = "OK" if mqtt_ok else "E"
        bottom_line = "{} W:{} M:{}".format(time_str, w_status, m_status)
        oled.text(bottom_line, 0, 48)
        
        oled.show()

# --- CẤU HÌNH MẠNG & MQTT (HIVEMQ CLOUD) ---
WIFI_SSID = "iloveyou3000"
WIFI_PASS = "33333333"

MQTT_BROKER    = "39d12a87b87b47f099d56965c5453701.s1.eu.hivemq.cloud"
MQTT_USER      = b"garden"
MQTT_PASSWORD  = b"Husc2026"
MQTT_PORT      = 8883
CLIENT_ID      = ubinascii.hexlify(machine.unique_id())

# --- BIẾN TRẠNG THÁI ---
isAuto = False
auto_time = "00:00"
isRepeat = False
auto_duration = 5 
is_pump_running_auto = False
pump_start_time = 0

wlan = network.WLAN(network.STA_IF)
wifi_ok = False
mqtt_ok = False
time_sync_ok = False # Biến cờ kiểm tra trạng thái đồng bộ thời gian
client = None

# Cấu hình lại server NTP của Google để đồng bộ nhanh và chính xác hơn
ntptime.host = "time.google.com"

def sync_time_ntp():
    global time_sync_ok
    try:
        print("Đang đồng bộ thời gian với Google NTP...")
        # Tạo độ trễ ngắn 500ms giúp phần cứng mạng ổn định định tuyến
        time.sleep_ms(500) 
        ntptime.settime()
        time_sync_ok = True
        print("Đã đồng bộ NTP thành công!")
        return True
    except Exception as e:
        time_sync_ok = False
        print("Đồng bộ NTP thất bại, sẽ thử lại sau:", e)
        return False

def connect_wifi():
    global wifi_ok
    wlan.active(True)
    if not wlan.isconnected():
        print("Đang kết nối WiFi...")
        wlan.connect(WIFI_SSID, WIFI_PASS)
        for _ in range(15):
            if wlan.isconnected():
                break
            time.sleep(1)
            
    if wlan.isconnected():
        wifi_ok = True
        print("WiFi Connected!", wlan.ifconfig())
        sync_time_ntp() # Tiến hành đồng bộ giờ lần đầu
    else:
        wifi_ok = False
        print("Lỗi: Không có kết nối WiFi")

def safe_publish(topic, msg):
    global mqtt_ok
    if mqtt_ok and client:
        try:
            client.publish(topic, msg)
        except OSError:
            mqtt_ok = False 

def sub_cb(topic, msg):
    global isAuto, auto_time, isRepeat, auto_duration, is_pump_running_auto
    topic = topic.decode()
    msg = msg.decode()
    print("Nhận MQTT:", topic, msg)

    if topic == "control":
        is_pump_running_auto = False # Hủy chế độ auto nếu có can thiệp thủ công
        
        # XỬ LÝ 4 VÙNG ĐỘC LẬP
        if msg == "0":
            set_devices(1, 1, 1, 1) # Bật tất cả
            safe_publish("weather", "on0")
        elif msg == "1":
            set_devices(1, 0, 0, 0) # Chỉ bật Relay 1
            safe_publish("weather", "on1")
        elif msg == "2":
            set_devices(0, 1, 0, 0) # Chỉ bật Relay 2
            safe_publish("weather", "on2")
        elif msg == "3":
            set_devices(0, 0, 1, 0) # Chỉ bật LED 1
            safe_publish("weather", "on3")
        elif msg == "4":
            set_devices(0, 0, 0, 1) # Chỉ bật LED 2
            safe_publish("weather", "on4")
        elif msg == "off":
            set_devices(0, 0, 0, 0) # Tắt tất cả
            safe_publish("weather", "off")
            
        elif msg.startswith("AUTO"):
            parts = msg.split("|")
            isAuto = (parts[1] == "1")
            auto_time = parts[2]
            isRepeat = (parts[3] == "1")
            if len(parts) >= 5:
                auto_duration = int(parts[4])
            print("Cập nhật hẹn giờ: {} - {} phút".format(auto_time, auto_duration))

def get_current_time_str():
    global time_sync_ok
    # Nếu chưa từng đồng bộ NTP thành công, trả về chữ "??:??" để dễ theo dõi lỗi thay vì hiện sai giờ
    if not time_sync_ok:
        return "??:??"
    try:
        t = time.localtime(time.time() + 7 * 3600)
        return "{:02d}:{:02d}".format(t[3], t[4])
    except:
        return "00:00"

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
last_ntp_retry = time.ticks_ms()

while True:
    try:
        current_str = get_current_time_str()
        current_sec = time.time()
        wifi_ok = wlan.isconnected()

        # --- TỰ ĐỘNG THỬ LẠI ĐỒNG BỘ NTP (Nếu lúc khởi động bị trượt) ---
        if wifi_ok and not time_sync_ok:
            if time.ticks_diff(time.ticks_ms(), last_ntp_retry) > 15000: # Cứ mỗi 15 giây xin lại giờ 1 lần
                sync_time_ntp()
                last_ntp_retry = time.ticks_ms()

        # --- AUTO RECONNECT MQTT ---
        if wifi_ok and not mqtt_ok:
            if time.ticks_diff(time.ticks_ms(), last_reconnect_try) > 10000:
                print("Đang thử khôi phục MQTT...")
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
                mqtt_ok = False

        # === LOGIC HẸN GIỜ (CHỈ CHẠY KHI ĐÃ ĐỒNG BỘ GIỜ THÀNH CÔNG) ===
        if time_sync_ok and isAuto and current_str == auto_time and not is_pump_running_auto:
            set_devices(1, 1, 1, 1) # Auto bật 4 vùng
            is_pump_running_auto = True
            pump_start_time = current_sec
            safe_publish("weather", "on0") # Báo cho App biết đã bật tất cả
            print("Bắt đầu tự động tưới toàn bộ.")

        if is_pump_running_auto:
            elapsed_seconds = current_sec - pump_start_time
            if elapsed_seconds >= (auto_duration * 60):
                set_devices(0, 0, 0, 0) # Auto tắt 4 vùng
                is_pump_running_auto = False
                safe_publish("weather", "off") # Báo cho App
                if not isRepeat:
                    isAuto = False

        # === ĐỌC CẢM BIẾN & CẬP NHẬT OLED ===
        if time.ticks_diff(time.ticks_ms(), last_sensor_read) > 5000:
            try:
                sensor_dht.measure()
                t = sensor_dht.temperature()
                h = sensor_dht.humidity()
                gas = gas_analog.read()
                
                update_oled(t, h, gas, current_str, wifi_ok, mqtt_ok)
                safe_publish("weather", "{}|{}".format(t, h))
            except Exception as e:
                print("Lỗi đọc cảm biến:", e)
                
            last_sensor_read = time.ticks_ms()
            
    except Exception as e:
        print("Lỗi vòng lặp:", e)      
        time.sleep(1)
        
    time.sleep(0.1)
