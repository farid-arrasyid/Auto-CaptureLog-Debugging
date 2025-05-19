#!/bin/sh
mkdir LogCapSW
chmod 777 LogCapSW
cd LogCapSW/
 
 
LOG_FILE="mnt/lg/cmn_data/LogCapSW/soc_temperature_log.txt"
store_dummy_json="/mnt/lg/cmn_data/LogCapSW/dummy.json"
 
# Main loop for running both task every 100 seconds
get_tv_info=$(luna-send -n 1 -f luna://com.webos.service.tv.systemproperty/getSystemInfo '{ "keys" : ["sdkVersion","boardType","modelName","firmwareVersion","SoCChipType"]}')
 
capture_log() {
    # Get model information
    model_name=$(node -pe 'JSON.parse(process.argv[1]).modelName' "$get_tv_info")
    board_type=$(node -pe 'JSON.parse(process.argv[1]).boardType' "$get_tv_info")
    firmware_version=$(node -pe 'JSON.parse(process.argv[1]).firmwareVersion' "$get_tv_info")
    version=$(cut -d ' ' -f 3-4 /etc/starfish-release | tr -d ' ')
    timestamp=$(date "+%Y-%m-%d_%H-%M-%S")
    # mac=`cat /sys/class/net/eth0/address | sed -e 's/://g'`
 
    name="High-SoC-Temp"-$timestamp-$model_name-$board_type-$version-$firmware_version.tgz
 
    # name=$timestamp-$model_name-$board_type-$version-$firmware_version.tgz
 
    luna-send -a com.palm.sample -n 1 luna://com.webos.notification/createToast '{
        "sourceId": "com.webos.service.pdm",
        "iconUrl": "/usr/share/physical-device-manager/usb_connect.png",
        "message": "log capture start",  
        "noaction": false
        }'
 
    # Get poser history in json
    luna-send -n 1 -f luna://com.webos.service.micomservice/requestPowerOnOffHistory '{"startIndex":0, "maxCount":127}' | node -e "
    process.stdin.on('data', data => {
    let jsonData;
    try {
        jsonData = JSON.parse(data);
    } catch (e) {
        console.error('Failed to parse JSON:', e);
        process.exit(1);
    }
    if (jsonData.reasonArray && Array.isArray(jsonData.reasonArray)) {
        jsonData.reasonArray = jsonData.reasonArray.map((item, index) => \`[\${index + 1}] \${item}\`);
    }
    console.log(JSON.stringify(jsonData, null, 2));
    });
    " >> powerhistory.json
 
    # Get pm log
    ifconfig -a >ifconfig.txt
    tar cvzf $name /ifconfig.txt /powerhistory.json /tmp/checkpoint/* /var/log/* /var/spool/* /var/db/* /var/lib/connman/* /var/run/nyx/* /mnt/lg/cmn_data/exc_*.txt /var/spool/rdxd/previous_boot_logs*.tar.gz
    sync
 
    chmod 777 $name
 
    rm ifconfig.txt
 
    if [ -f $name ]; then
        luna-send -a com.palm.sample -n 1 luna://com.webos.notification/createToast '{
            "sourceId": "com.webos.service.pdm",
            "iconUrl": "/usr/share/physical-device-manager/usb_connect.png",
            "message": "log capture complete",  
            "noaction": false
            }'
    fi
}
 
while true; do
    touch soc_temperature_log.txt
    # Generate JSON dummy with currentTemperature = 100
    tempData=$(luna-send -n 1 -f luna://com.webos.service.fancontroller/getThermalReport '{}')
    echo "succeed to read SoC Temperature data"
    echo $(date "+%Y-%m-%d %H:%M:%S") $tempData >>soc_temperature_log.txt
    echo "succeed to save SoC Temperature data in mnt/lg/cmn_data/soc_temperature_log.txt"
    # Parsing JSON to get currentTemperature
    echo $tempData >>$store_dummy_json
    current_temp=$(node -pe 'JSON.parse(process.argv[1]).soc.currentTemperature' "$(cat dummy.json)")
    # Check whether currentTemperature reaches or exceeds 100
    if [ $current_temp -ge 50 ]; then
        # Send Alert High Temperature
        luna-send -n 1 -f -a com.webos.surfacemanager luna://com.webos.notification/createAlert '{
            "message":"High SoC Temperature Detected",
            "buttons":[{"label":"Do Not Send Any Input","params":{"id":"youtube.leanback.v4"}}]}'
        capture_log
        # Read and save SoC data
        # soc_temp=`node -pe 'JSON.parse(process.argv[1]).soc.currentTemperature' "$(cat dummy.json)"`
        # echo "$(date '+%Y-%m-%d %H:%M:%S') - SoC Temperature: $soc_temp°C" >> "$LOG_FILE"
        # echo $soc_temp >> $LOG_FILE
        #cat /proc/thermalinfo/soc_temperature > "$STORE_PATH/soc_temperature.log"  # Note: Make sure this is the right path
        rm dummy.json
        # Set trap to handle SIGINT
        exit 1
    fi
    echo "SoC Temperature Normal"
    # clean up dummy.json file
    rm dummy.json
    # Ensure sleep goes well
    sleep 2 # 100 seconds
done