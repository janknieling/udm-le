#!/bin/sh

# Set data dir
DATA_DIR="/mnt/data"
case "$(ubnt-device-info firmware || true)" in
    1*)
      DATA_DIR="/mnt/data"
      ;;
    2*)
      DATA_DIR="/data"
      ;;
    3*)
      DATA_DIR="/data"
      ;;
    *)
      echo "ERROR: No persistent storage found." 1>&2
      exit 1
      ;;
  esac


# Load Environmnt Variables
. $DATA_DIR/udm-le/udm-le.env

if [ ! -f /etc/cron.d/udm-le ]; then
	# Sleep for 5 minutes to avoid restarting
	# services during system startup.
	sleep 300
	sh ${UDM_LE_PATH}/udm-le.sh renew --restart-services
fi
