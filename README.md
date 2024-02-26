# Fancontrol
Openwrt简易通用风扇控制，最早是给GL-AXT1800使用，原理是读取系统温度，然后根据不同温度无级别调节风扇速度。

## 安装步骤
###  Add this repo as an OpenWrt feed

1. Add new feed:
    ```bash
    echo "src-git fancontrol https://github.com/JiaY-shi/fancontrol.git" >> "feeds.conf"
    ```
2. Pull upstream commits:
    ```bash
    ./scripts/feeds update fancontrol && ./scripts/feeds install -a -f -p fancontrol
    ```
- Remove
    ```bash
    sed -i "/fancontrol/d" "feeds.conf"
    ./scripts/feeds clean && ./scripts/feeds update -a && ./scripts/feeds install -a
    ```
## 预览
![图片](./images/1.png)
