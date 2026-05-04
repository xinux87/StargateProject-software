#!/bin/bash

function disable_onboard_audio() {
  # Disable the onboard audio adapter
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
  # Configure ALSA to use the external audio adapter Check your USB position on the "aplay -l"
  echo 'Configuring ALSA to use external USB audio adapter'
  CONFIG='/usr/share/alsa/alsa.conf'
  TEMP='alsa.temp'
  SETTING='2'
  sudo cp $CONFIG $TEMP
  sudo sed -i -e "s/defaults\.ctl\.card [01]/defaults.ctl.card $SETTING/g" \
  -e "s/defaults\.ctl\.card [01]/defaults.ctl.card $SETTING/g" $TEMP
  sudo sed -i -e "s/defaults\.ctl\.card [01]/defaults.ctl.card $SETTING/g" \
  -e "s/defaults\.pcm\.card [01]/defaults.pcm.card $SETTING/g" $TEMP
  sudo mv $TEMP $CONFIG
}

disable_onboard_audio
configure_audio

exit 0
