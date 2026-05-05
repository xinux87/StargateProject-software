
# Detect the real user even when invoked via sudo
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
SG1_DIR="$USER_HOME/sg1_v4"
VENV_DIR="$USER_HOME/venv_v4"

function verify_stargate_software_or_exit() {
  [ ! -d '../classes' ] && echo "Upload the Software $SG1_DIR before continuing" && exit 1
  [ ! -d '../soundfx' ] && echo "Upload the Audio clips $SG1_DIR/soundfx/(milkyway|pegasus) before continuing" && exit 1
  echo 'Version 4.x Software installation detected'
}

function enable_ssh() {
  # Enable SSH
  echo 'Enabling SSH'
  sudo raspi-config nonint do_ssh 0
}


function set_permissions() {
  # Set permissions on the scripts
  echo 'Configuring permissions on Stargate Scripts'
  [ -d "$SG1_DIR/util" ] && sudo chmod u+x "$SG1_DIR/util/"*
  [ -d "$SG1_DIR/scripts" ] && sudo chmod u+x "$SG1_DIR/scripts/"*
}

function do_hardware_config() {
  # Enable SPI
  echo 'Enabling SPI'
  sudo raspi-config nonint do_spi 0

  # Enable I2C
  echo 'Enabling I2C'
  sudo raspi-config nonint do_i2c 0

  # Enable Boot/Autologin to Console Autologin
  echo 'Configuring Auto Login via Console on Boot'
  sudo raspi-config nonint do_boot_behaviour B2
}

function apt_update_and_install() {
  # Update and Upgrade system packages
  echo 'Updating, upgrading system packages...this may take a while.'
  sudo apt-get update -y | sed 's/^/     /'
  sudo apt-get upgrade -y | sed 's/^/     /'

  # Install system-level dependencies
  echo 'Installing system-level dependencies...this may take a while.'
  sudo apt-get install --no-install-recommends -y nano clang python3-dev python3-venv libasound2-dev avahi-daemon apache2 ufw python3-smbus i2c-tools netcat-traditional python3-RPi.GPIO | sed 's/^/     /'
}

function init_venv() {
  # Create the virtual environment
  cd "$USER_HOME"

  # Remove the env if it already exists
  [ -d "$VENV_DIR" ] && rm -Rf "$VENV_DIR"

  echo "Initializing Python virtual environment in $VENV_DIR"
  python3 -m venv "$VENV_DIR"

  # Activate the venv and install some dependencies
  echo 'Installing pip setuptools into the virtual environment'
  source "$VENV_DIR/bin/activate"
  export CFLAGS=-fcommon
  pip install setuptools | sed 's/^/     /'

  # Install requirements.txt pip packages
  echo 'Installing requirements.txt dependencies into the Virtual Environment'
  pip install -r "$SG1_DIR/requirements.txt" | sed 's/^/     /'

  echo 'Deactivating the virtual environment'
  deactivate
}

function configure_hostname() {
  # Update the hostname to "stargate" so we can use "stargate.local" via Bonjour
  echo 'Configuring hostname for stargate.local Bonjour'
  sudo raspi-config nonint do_hostname stargate > /dev/null
  sudo hostnamectl set-hostname stargate > /dev/null

  CONFIG='/etc/hosts'
  if grep -Fq '127.0.1.1    stargate' $CONFIG > /dev/null
  then
      echo 'hosts file already configured'
  else
      echo 'Configuring hosts file'
      sudo sed -i '$i\\r\n127.0.1.1    stargate\r\n' $CONFIG > /dev/null
      sudo sort -u /etc/hosts > /tmp/hosts.new && sudo mv /tmp/hosts.new /etc/hosts
  fi
}

function configure_apache() {

  echo 'Apache Web Server Config: Start'
  echo 'Adding Stargate API Apache Configuration'

  sudo tee /etc/apache2/conf-available/stargate_api.conf > /dev/null <<EOT
<Directory $SG1_DIR/web>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
ProxyPass     /stargate/     http://localhost:8080/ retry=0
EOT

  echo 'Enabling Stargate API Apache Configuration'
  sudo ln -sf /etc/apache2/conf-available/stargate_api.conf /etc/apache2/conf-enabled/stargate_api.conf

  echo "Configuring Apache to run the server as user and group '$REAL_USER'"
  sudo sed -i "s/export APACHE_RUN_USER=.*/export APACHE_RUN_USER=$REAL_USER/" /etc/apache2/envvars
  sudo sed -i "s/export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=$REAL_USER/" /etc/apache2/envvars

  echo 'Configure the virtualhost DocumentRoot'
  sudo sed -i "s|\(DocumentRoot *\).*|\1$SG1_DIR/web|" /etc/apache2/sites-available/000-default.conf

  # Enable ModProxy and ModProxyHTTP
  echo 'Apache Config: Enabling required modules.'
  cd /etc/apache2/mods-enabled
  sudo ln -sf ../mods-available/proxy.conf proxy.conf
  sudo ln -sf ../mods-available/proxy.load proxy.load
  sudo ln -sf ../mods-available/proxy_http.load proxy_http.load
}

function restart_apache() {
  echo 'Apache Config: service restart to load configs.'
  sudo service apache2 restart
}

function configure_crontab() {
  echo "Configuring crontab (user: $REAL_USER)"
  (sudo -u "$REAL_USER" crontab -l 2>/dev/null; echo "*/8 * * * * $VENV_DIR/bin/python3 $SG1_DIR/scripts/speaker_on.py") | awk '!x[$0]++' | sudo -u "$REAL_USER" crontab -
}

function disable_pwr_mgmt() {
  echo 'Disabling WiFi power management'
  CONFIG='/etc/rc.local'

  if [ ! -f "$CONFIG" ]; then
      echo '#!/bin/sh -e' | sudo tee "$CONFIG" > /dev/null
      echo 'exit 0' | sudo tee -a "$CONFIG" > /dev/null
      sudo chmod +x "$CONFIG"
      echo "Created $CONFIG file"
  fi

  if grep -Fq '/sbin/iw wlan0 set power_save off' $CONFIG
  then
      echo 'WiFi power management is already disabled'
  else
      echo 'Disabling WiFi power management'
      sudo sed -i '$i\\r\n/sbin\/iw wlan0 set power_save off\r\n' $CONFIG
  fi
}

function disable_onboard_audio() {
  sudo cp /boot/config.txt /boot/config.bak
  echo 'Disabling RaspberryPi on-board audio adapter'
  CONFIG='/boot/firmware/config.txt'
  SETTING='off'
  sudo sed $CONFIG -i -r -e "s/^((device_tree_param|dtparam)=([^,]*,)*audio?)(=[^,]*)?/\1=$SETTING/"
  if ! grep -q -E '^(device_tree_param|dtparam)=([^,]*,)*audio?=[^,]*' $CONFIG; then
    echo 'pattern not found, creating'
    printf "dtparam=audio=$SETTING\n" >> $CONFIG
  fi
}

function configure_audio() {
  echo 'Configuring ALSA to use external USB audio adapter'
  CONFIG='/usr/share/alsa/alsa.conf'
  TEMP='alsa.temp'
  SETTING='1'
  sudo cp $CONFIG $TEMP
  sudo sed -i -e "s/defaults\.ctl\.card [01]/defaults.ctl.card $SETTING/g" \
  -e "s/defaults\.ctl\.card [01]/defaults.ctl.card $SETTING/g" $TEMP
  sudo sed -i -e "s/defaults\.ctl\.card [01]/defaults.ctl.card $SETTING/g" \
  -e "s/defaults\.pcm\.card [01]/defaults.pcm.card $SETTING/g" $TEMP
  sudo mv $TEMP $CONFIG
}

function configure_logrotate() {
  echo 'Configuring logrotate'
  sudo tee -a /etc/logrotate.d/stargate > /dev/null <<EOT
$SG1_DIR/logs/*.log {
    missingok
    notifempty
    size 30k
    daily
    rotate 30
    create 0600 $REAL_USER $REAL_USER
}
EOT
}

function configure_systemd_service() {
  echo 'Adding systemd service'
  sudo tee /etc/systemd/system/stargate.service > /dev/null <<EOT
[Unit]
Description=BuildAStargate.com Stargate Daemon (SG1)
Requires=multi-user.target
After=multi-user.target rc-local.service
AllowIsolate=yes

[Service]
Type=simple
WorkingDirectory=$SG1_DIR
ExecStart=$VENV_DIR/bin/python3 $SG1_DIR/main.py --daemon

[Install]
WantedBy=multi-user.target

EOT

  echo 'Reloading systemd daemon configs'
  sudo systemctl daemon-reload

  echo 'Enabling stargate.service in the normal runlevels'
  sudo systemctl enable stargate.service

  sudo systemctl stop stargate.service
  sudo systemctl start stargate.service

}

function configure_firewall_ufw() {
  echo 'Configuring firewall'

  sudo ufw reload
  sudo ufw deny in on any
  sudo ufw allow OpenSSH
  sudo ufw allow http
  sudo ufw allow 8080/tcp

  echo 'Enabling firewall'
  echo "y" | sudo ufw enable
}
