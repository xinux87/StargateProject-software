#!/usr/bin/python3
# pylint: disable=wrong-import-position

# SPDX-FileCopyrightText: 2021 ladyada for Adafruit Industries
# SPDX-License-Identifier: MIT

"""Simple test for a standard servo on channel 0 and a continuous rotation servo on channel 1."""
import time
from adafruit_servokit import ServoKit

from gpiozero import LED # pylint: disable=import-error


# Set channels to the number of servo channels on your kit.
# 8 for FeatherWing, 16 for Shield/HAT/Bonnet.
kit = ServoKit(channels=16)
led_channels =  {
            LED(21),
            LED(20),
            LED(19),
            LED(16),
            LED(13),
            LED(12),
            LED(6),
        }
while True:
    for i in range(7):
        kit.continuous_servo[i].throttle = -0.5
    for leds in led_channels:
        leds.on()
    time.sleep(2.0)
    for i in range(8):
        kit.continuous_servo[i].throttle = 0.50
    for leds in led_channels:
        leds.off()
    time.sleep(2.0)
        

