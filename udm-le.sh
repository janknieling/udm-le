#!/bin/sh

set -e

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

# Set UDM_LE_PATH
UDM_LE_PATH="$DATA_DIR/udm-le"

# Load environment variables
. $DATA_DIR/udm-le/udm-le.env

# Check UniFi Dream Machine model and firmware version and print out to console
udm_model() {
  case "$(ubnt-device-info model || true)" in
    "UniFi Dream Machine SE")
      echo "udmse"
      ;;
    "UniFi Dream Machine Pro")
      if test $(ubnt-device-info firmware) \< "2.0.0"; then 
        echo "udmprolegacy"
      else 
        echo "udmpro"
      fi
      ;;
    "UniFi Dream Machine")
      if test $(ubnt-device-info firmware) \< "2.0.0"; then 
        echo "udmlegacy"
      else 
        echo "udm"
      fi
      ;;
    "UniFi Dream Router")
      echo "udr"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}




# Setup variables for later
DOCKER_VOLUMES="-v ${UDM_LE_PATH}/lego/:/.lego/"
LEGO_ARGS="--dns ${DNS_PROVIDER} --email ${CERT_EMAIL} --key-type rsa2048"
RESTART_SERVICES=false

# Show usage
usage()
{
  echo "Usage: udm-le.sh action [ --restart-services ]"
  echo "Actions:"
  echo "	- udm-le.sh initial: Generate new certificate and set up cron job to renew at 03:00 each morning."
  echo "	- udm-le.sh renew: Renew certificate if due for renewal."
  echo "	- udm-le.sh update_keystore --restart-services: Update keystore used by Captive Portal/WiFiman"
  echo "	  with either full certificate chain (if NO_BUNDLE='no') or server certificate only (if NO_BUNDLE='yes')."
  echo "	  Requires --restart-services flag. "
  echo ""
  echo "Options:"
  echo "	--restart-services: [optional] force restart of services even if certificate not renewed."
  echo ""
  echo "WARNING: NO_BUNDLE option is only supported experimentally. Setting it to 'yes' is required to make WiFiman work,"
  echo "but may result in some clients not being able to connect to Captive Portal if they do not already have a cached"
  echo "copy of the CA intermediate certificate(s) and are unable to download them."
}

# Get command line options
OPTIONS=$(getopt -o h --long help,restart-services -- "$@")
if [[ $? -ne 0 ]]; then
    echo "Incorrect option provided"
    exit 1;
fi

eval set -- "$OPTIONS"
while [ : ]; do
  case "$1" in
    -h | --help)
		usage;
		exit 0;
		shift
		;;
    --restart-services)
        RESTART_SERVICES=true;
        shift
        ;;
    --) shift; 
        break 
        ;;
  esac
done

deploy_certs_1-x() {
	# Deploy certificates for the controller and optionally for the captive portal and radius server

	# Re-write CERT_NAME if it is a wildcard cert. Replace * with _
	LEGO_CERT_NAME=${CERT_NAME/\*/_}
	if [ "$(find -L "${UDM_LE_PATH}"/lego -type f -name "${LEGO_CERT_NAME}".crt -mmin -5)" ]; then
		echo 'New certificate was generated, time to deploy it'

		cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.crt ${UBIOS_1-X_CONTROLLER_CERT_PATH}/unifi-core.crt
		cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.key ${UBIOS_1-X_CONTROLLER_CERT_PATH}/unifi-core.key
		chmod 644 ${UBIOS_1-X_CONTROLLER_CERT_PATH}/unifi-core.crt ${UBIOS_1-X_CONTROLLER_CERT_PATH}/unifi-core.key

		if [ "$ENABLE_CAPTIVE" == "yes" ]; then
			update_keystore
		fi

		if [ "$ENABLE_RADIUS" == "yes" ]; then
			cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.crt ${UBIOS_1-X_RADIUS_CERT_PATH}/server.pem
			cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.key ${UBIOS_1-X_RADIUS_CERT_PATH}/server-key.pem
			chmod 600 ${UBIOS_1-X_RADIUS_CERT_PATH}/server.pem ${UBIOS_1-X_RADIUS_CERT_PATH}/server-key.pem
		fi

		RESTART_SERVICES=true
	fi
}

deploy_certs_2-x() {
	# Deploy certificates for the controller and optionally for the captive portal and radius server

	# Re-write CERT_NAME if it is a wildcard cert. Replace * with _
	LEGO_CERT_NAME=${CERT_NAME/\*/_}
	if [ "$(find -L "${UDM_LE_PATH}"/lego -type f -name "${LEGO_CERT_NAME}".crt -mmin -5)" ]; then
		echo 'New certificate was generated, time to deploy it'

		cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.crt ${UBIOS_2-X_CONTROLLER_CERT_PATH}/unifi-core.crt
		cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.key ${UBIOS_2-X_CONTROLLER_CERT_PATH}/unifi-core.key
		chmod 644 ${UBIOS_2-X_CONTROLLER_CERT_PATH}/unifi-core.crt ${UBIOS_2-X_CONTROLLER_CERT_PATH}/unifi-core.key

		if [ "$ENABLE_CAPTIVE" == "yes" ]; then
			update_keystore
		fi

		if [ "$ENABLE_RADIUS" == "yes" ]; then
			cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.crt ${UBIOS_2-X_RADIUS_CERT_PATH}/server.pem
			cp -f ${UDM_LE_PATH}/lego/certificates/${LEGO_CERT_NAME}.key ${UBIOS_2-X_RADIUS_CERT_PATH}/server-key.pem
			chmod 600 ${UBIOS_2-X_RADIUS_CERT_PATH}/server.pem ${UBIOS_2-X_RADIUS_CERT_PATH}/server-key.pem
		fi

		RESTART_SERVICES=true
	fi
}

restart_services_1-X() {
	# Restart services if certificates have been deployed, or we're forcing it on the command line
	if [ "${RESTART_SERVICES}" == true ]; then
		echo 'Restarting UniFi OS'
		unifi-os restart &>/dev/null

		if [ "$ENABLE_RADIUS" == "yes" ]; then
			echo 'Restarting Radius server'
			if [ -x "$(command -v rc.radius)" ]; then 
				rc.radius restart &>/dev/null
			elif [ -x "$(command -v rc.radiusd)" ];then 
				rc.radiusd restart &>/dev/null
			else
				echo 'Radius command not found'
			fi
		fi
	else
		echo 'RESTART_SERVICES is false, skipping service restarts'
	fi
}

restart_services_2-X() {
	# Restart services if certificates have been deployed, or we're forcing it on the command line
	if [ "${RESTART_SERVICES}" == true ]; then
		echo 'Restarting UniFi OS'
		systemctl restart unifi-core &>/dev/null
		systemctl restart unifi &>/dev/null

		if [ "$ENABLE_RADIUS" == "yes" ]; then
			echo 'Restarting Radius server'
			if [ -x "$(command -v rc.radius)" ]; then 
				rc.radius restart &>/dev/null
			elif [ -x "$(command -v rc.radiusd)" ];then 
				rc.radiusd restart &>/dev/null
			else
				echo 'Radius command not found'
			fi
		fi
	else
		echo 'RESTART_SERVICES is false, skipping service restarts'
	fi
}

update_keystore_1-x() {
	if [ "$NO_BUNDLE" == "yes" ]; then
		# Only import server certifcate to keystore. WiFiman requires a single certificate in the .crt file 
		# and does not work if the full chain is imported as this includes the CA intermediate certificates.
		echo "	- Importing server certificate only"
		# 1. Export only the server certificate from the full chain bundle
		podman exec -it unifi-os openssl x509 -in ${UNIFIOS_1-X_CERT_PATH}/unifi-core.crt > ${UNIFIOS_1-X_CERT_PATH}/unifi-core-server-only.crt
		# 2. Bundle the private key and server-only certificate into a PKCS12 format file
		podman exec -it unifi-os openssl pkcs12 -export -inkey ${UNIFIOS_1-X_CERT_PATH}/unifi-core.key -in ${UNIFIOS_1-X_CERT_PATH}/unifi-core-server-only.crt \
			-out ${UNIFIOS_1-X_KEYSTORE_PATH}/unifi-core-key-plus-server-only-cert.p12 -name ${UNIFIOS_1-X_KEYSTORE_CERT_ALIAS} -password pass:${UNIFIOS_1-X_KEYSTORE_PASSWORD}
		# 3. Backup the keystore before editing it.
		podman exec -it unifi-os cp ${UNIFIOS_1-X_KEYSTORE_PATH}/keystore ${UNIFIOS_1-X_KEYSTORE_PATH}/keystore_$(date +"%Y-%m-%d_%Hh%Mm%Ss").backup
		# 4. Delete the existing full chain from the keystore
		podman exec -it unifi-os keytool -delete -alias unifi -keystore ${UNIFIOS_1-X_KEYSTORE_PATH}/keystore -deststorepass ${UNIFIOS_1-X_KEYSTORE_PASSWORD}
		# 5. Import the server-only certificate and private key from the PKCS12 file
		podman exec -it unifi-os keytool -importkeystore -deststorepass ${UNIFIOS_1-X_KEYSTORE_PASSWORD} -destkeypass ${UNIFIOS_1-X_KEYSTORE_PASSWORD} \
			-destkeystore ${UNIFIOS_1-X_KEYSTORE_PATH}/keystore -srckeystore ${UNIFIOS_1-X_KEYSTORE_PATH}/unifi-core-key-plus-server-only-cert.p12 \
			-srcstoretype PKCS12 -srcstorepass ${UNIFIOS_1-X_KEYSTORE_PASSWORD} -alias ${UNIFIOS_1-X_KEYSTORE_CERT_ALIAS} -noprompt
	else
		# Import full certificate chain bundle to keystore
		echo "	- Importing full certificate chain bundle"
		podman exec -it unifi-os ${CERT_IMPORT_CMD_1-X} ${UNIFIOS_1-X_CERT_PATH}/unifi-core.key ${UNIFIOS_1-X_CERT_PATH}/unifi-core.crt
	fi
}

update_keystore_2-x() {
	if [ "$NO_BUNDLE" == "yes" ]; then
		# Only import server certifcate to keystore. WiFiman requires a single certificate in the .crt file 
		# and does not work if the full chain is imported as this includes the CA intermediate certificates.
		echo "	- Importing server certificate only"
		# 1. Export only the server certificate from the full chain bundle
		openssl x509 -in ${UNIFIOS_2-X_CERT_PATH}/unifi-core.crt > ${UNIFIOS_2-X_CERT_PATH}/unifi-core-server-only.crt
		# 2. Bundle the private key and server-only certificate into a PKCS12 format file
		openssl pkcs12 -export -inkey ${UNIFIOS_2-X_CERT_PATH}/unifi-core.key -in ${UNIFIOS_2-X_CERT_PATH}/unifi-core-server-only.crt \
			-out ${UNIFIOS_2-X_KEYSTORE_PATH}/unifi-core-key-plus-server-only-cert.p12 -name ${UNIFIOS_2-X_KEYSTORE_CERT_ALIAS} -password pass:${UNIFIOS_2-X_KEYSTORE_PASSWORD}
		# 3. Backup the keystore before editing it.
		cp ${UNIFIOS_2-X_KEYSTORE_PATH}/keystore ${UNIFIOS_2-X_KEYSTORE_PATH}/keystore_$(date +"%Y-%m-%d_%Hh%Mm%Ss").backup
		# 4. Delete the existing full chain from the keystore
		keytool -delete -alias unifi -keystore ${UNIFIOS_2-X_KEYSTORE_PATH}/keystore -deststorepass ${UNIFIOS_2-X_KEYSTORE_PASSWORD}
		# 5. Import the server-only certificate and private key from the PKCS12 file
		keytool -importkeystore -deststorepass ${UNIFIOS_2-X_KEYSTORE_PASSWORD} -destkeypass ${UNIFIOS_2-X_KEYSTORE_PASSWORD} \
			-destkeystore ${UNIFIOS_2-X_KEYSTORE_PATH}/keystore -srckeystore ${UNIFIOS_2-X_KEYSTORE_PATH}/unifi-core-key-plus-server-only-cert.p12 \
			-srcstoretype PKCS12 -srcstorepass ${UNIFIOS_2-X_EYSTORE_PASSWORD} -alias ${UNIFIOS_2-X_KEYSTORE_CERT_ALIAS} -noprompt
	else
		# Import full certificate chain bundle to keystore
		echo "	- Importing full certificate chain bundle"
		${CERT_IMPORT_CMD_2-X} ${UNIFIOS_2-X_CERT_PATH}/unifi-core.key ${UNIFIOS_CERT_PATH}/unifi-core.crt
	fi
}

# Support alternative DNS resolvers
if [ "${DNS_RESOLVERS}" != "" ]; then
	LEGO_ARGS="${LEGO_ARGS} --dns.resolvers ${DNS_RESOLVERS}"
fi

# Support multiple certificate SANs
for DOMAIN in $(echo $CERT_HOSTS | tr "," "\n"); do
	if [ -z "$CERT_NAME" ]; then
		CERT_NAME=$DOMAIN
	fi
	LEGO_ARGS="${LEGO_ARGS} -d ${DOMAIN}"
done



# Setup persistent on_boot.d trigger
ON_BOOT_DIR='$DATA_DIR/on_boot.d'
ON_BOOT_FILE='99-udm-le.sh'
if [ -d "${ON_BOOT_DIR}" ] && [ ! -f "${ON_BOOT_DIR}/${ON_BOOT_FILE}" ]; then
	cp "${UDM_LE_PATH}/on_boot.d/${ON_BOOT_FILE}" "${ON_BOOT_DIR}/${ON_BOOT_FILE}"
	chmod 755 ${ON_BOOT_DIR}/${ON_BOOT_FILE}
fi

# Setup nightly cron job
CRON_FILE='/etc/cron.d/udm-le'
if [ ! -f "${CRON_FILE}" ]; then
	echo "0 3 * * * sh ${UDM_LE_PATH}/udm-le.sh renew" >${CRON_FILE}
	chmod 644 ${CRON_FILE}
	/etc/init.d/crond reload ${CRON_FILE}
fi

run_unifios_1-x() {
	# Check for optional .secrets directory, and add it to the mounts if it exists
	# Lego does not support AWS_ACCESS_KEY_ID_FILE or AWS_PROFILE_FILE so we'll try
	# mounting the secrets directory into a place that Route53 will see.
	if [ -d "${UDM_LE_PATH}/.secrets" ]; then
		DOCKER_VOLUMES="${DOCKER_VOLUMES} -v ${UDM_LE_PATH}/.secrets:/root/.aws/ -v ${UDM_LE_PATH}/.secrets:/root/.secrets/"
	fi
	
	PODMAN_CMD="podman run --env-file=${UDM_LE_PATH}/udm-le.env -it --name=lego --network=host --rm ${DOCKER_VOLUMES} ${CONTAINER_IMAGE}:${CONTAINER_IMAGE_TAG}"

	case $1 in
	initial)
		# Create lego directory so the container can write to it
		if [ "$(stat -c '%u:%g' "${UDM_LE_PATH}/lego")" != "1000:1000" ]; then
			mkdir "${UDM_LE_PATH}"/lego
			chown 1000:1000 "${UDM_LE_PATH}"/lego
		fi

		echo 'Attempting initial certificate generation'
		${PODMAN_CMD} ${LEGO_ARGS} --accept-tos run && deploy_certs_1-x && restart_services_1-x
		;;
	renew)
		echo 'Attempting certificate renewal'
		echo ${PODMAN_CMD} ${LEGO_ARGS}
		${PODMAN_CMD} ${LEGO_ARGS} renew --days 60 && deploy_certs_1-x && restart_services_1-x
		;;
	test_deploy)
		echo 'Attempting to deploy certificate'
		deploy_certs_1-x
		;;
	update_keystore)
		echo 'Attempting to update keystore used by hotspot Captive Portal and WiFiman'
		update_keystore_1-x && restart_services_1-x
		;;
	*)
		echo "ERROR: No valid action provided."
		usage;
		exit 1;
	esac	
}

run_unifios_2-x() {
	# Create LEGO directory
	mkdir "${UDM_LE_PATH}"/lego
	# Download latest LEGO binaries
	curl -o /tmp/"${LEGO_VERSION}" ${LEGO_RELEASE_URL}/${LEGO_VERSION}
	# Unpack LEGO to UDM_LE_PATH
	tar -xzf /tmp/"${LEGO_VERSION}" -C "${UDM_LE_PATH}"/lego
	# Make it executable
	chmod +x "${UDM_LE_PATH}"/lego/lego

	LEGO_CMD="${UDM_LE_PATH}"/lego/lego

	case $1 in
	initial)
		echo 'Attempting initial certificate generation'
		${LEGO_CMD} ${LEGO_ARGS} --accept-tos run && deploy_certs_2-x && restart_services_2-x
		;;
	renew)
		echo 'Attempting certificate renewal'
		echo ${LEGO_CMD} ${LEGO_ARGS}
		${LEGO_CMD} ${LEGO_ARGS} renew --days 60 && deploy_certs_2-x && restart_services_2-x
		;;
	test_deploy)
		echo 'Attempting to deploy certificate'
		deploy_certs_2-x
		;;
	update_keystore)
		echo 'Attempting to update keystore used by hotspot Captive Portal and WiFiman'
		update_keystore_2-x && restart_services_2-x
		;;
	*)
		echo "ERROR: No valid action provided."
		usage;
		exit 1;
	esac	

}

case "$(udm_model)" in
  udmlegacy|udmprolegacy)
    echo "$(ubnt-device-info model) version $(ubnt-device-info firmware) was detected"
	echo "installing udm-le using podman"
	depends_on podman
	run_unifios_1-x

  udr|udmse|udm|udmpro)
    echo "$(ubnt-device-info model) version $(ubnt-device-info firmware) was detected"
    echo "Installing udm-le using lego binaries"
    depends_on systemctl
	run_unifios_2-x
esac
