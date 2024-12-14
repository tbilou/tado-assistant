# Tado-Assistant OpenWrt

I came across this amazing [bash script](https://github.com/BrainicHQ/) called **tado-assistant** that provides a free alternative to Tado's Auto-Assist paid subscription.

You can run the Tado-Assistant bash script almost everywhere (docker, VPC, rpi, etc)

However, the only device that I have running 24/7 at home is my router running [OpenWrt](https://openwrt.org/)

So I adapted the tado assistant to run on ash instead of bash. (should be POSIX compatible)

## ⚠️ **Disclaimer**
You're better of using the [tado -assistant bash script](https://github.com/BrainicHQ/).
I adapted the original script for my own personal use and in doing so removed a couple of features from the original bash script:
* ~~Multi-Account Support~~ - It's just for me, so single user is fine
* ~~Instalation script~~ - I'm not planning on installing it again, so I just defined the properties in the `tado-assistant.sh` script
* ~~Customizable open window duration~~ - I don't have a need to override the time I define in the Tado app.
* ~~Geofencing~~ - I never wanted to use geofencing anyway, so replaced it with "Phone presence"
* ~~V3 API~~ - I have the tado X and they use a different API

## 📞 Phone presence
Because the script is running inside the router it's very simple to know which devices are connected to it. 
There are two Mac addresses configured in the script. When all phones are out of the house (disconnected from the wifi) it turns off the heating.

### 🌟 New API for Tado X line of products
I have the Tado Smart Radiator **X** and aparentely these use a different API than the previous generation (V3) that is used by the original bash script.
