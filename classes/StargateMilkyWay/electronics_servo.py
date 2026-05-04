from adafruit_motorkit import MotorKit # pylint: disable=import-error
from adafruit_motor import stepper as stp
# import neopixel # pylint: disable=import-error
import board # pylint: disable=import-error
from gpiozero import LED # pylint: disable=import-error

from hardware_simulation import DCMotorSim, StepperSim, LEDSim
from stargate_config import StargateConfig

from hardware_simulation import NeopixelSim
from adafruit_servokit import ServoKit

from electronics_servo_helpers import SERVOMotor

class Electronics_Servo:

    def __init__(self, app):

        self.cfg = app.cfg
        self.log = app.log

        self.name = "Electronics Servo PCA9685 Board + Adafruit HAT"

        self.log.log(f"Loaded Board: {self.name}")

        self.stepper_motor_enable = self.cfg.get("stepper_motor_enable")
        self.chevron_motors_enable = self.cfg.get("chevron_motors_enable")

         ### Load our board-specific config file.
        self.board_cfg = StargateConfig(app.base_path, "board_servo", app.galaxy_path)
        self.board_cfg.set_log(app.log)
        self.board_cfg.load()

        #configuration BOARD1. 40 PWM Board for the servos
        self._pwm_board_addr = 0x40
        self._pwm_PCA9685_frequency = 60.0
        self._pwm_board_servos = ServoKit(channels=16)


        #Configuration BOARD2. 60 - 70 ADAFRUIT BOARD
        self._motor_shield_addr = 0x60
        self._pwm_frequency = 1600.0
        self._stepper_microsteps = 16

        #configuration for the ledring.
        self.neopixel_pin = board.D12
        self.neopixel_led_count = 122

    # ------------------------------------------ UNUSSED

        self.adc_resolution = None
        self.adc_vref = None
        self.motor_channels = None
        self.led_channels = None
        self.stepper = None
        self.spi = None
     # ------------------------------------------ INITIALIZATION

        self.init_motor_shields()
        self.init_led_gpio()

        self.drive_modes = {
            "double": stp.DOUBLE,
            "single": stp.SINGLE,
            "interleave": stp.INTERLEAVE,
            "microstep": stp.MICROSTEP
        }

        self.neopixels = None
        self.init_neopixels()

        

        self.log.log(f"Hardware Detected: {self.name}")

    def init_motor_shields(self):
        # Initialize all of the shields as DC motors
        self.motor_channels =  {
            1: self._pwm_board_servos.continuous_servo[0],
            2: self._pwm_board_servos.continuous_servo[1],
            3: self._pwm_board_servos.continuous_servo[2],
            4: self._pwm_board_servos.continuous_servo[3],
            5: self._pwm_board_servos.continuous_servo[4],
            6: self._pwm_board_servos.continuous_servo[5],
            7: self._pwm_board_servos.continuous_servo[6],
            8: DCMotorSim(),
            9: DCMotorSim()
        }

        # Initialize the Stepper
        # Initialize the Stepper
        if self.stepper_motor_enable:
            self.stepper = MotorKit(address=self._motor_shield_addr).stepper1
        else:
            self.stepper = StepperSim()

    def init_led_gpio(self):
        self.led_channels =  {
            1: LED(6),
            2: LED(12),
            3: LED(13),
            4: LED(16),
            5: LED(19),
            6: LED(20),
            7: LED(21),
            8: LEDSim(),
            9: LEDSim()
        }

    def get_chevron_motor(self, chevron_number):
        return self.motor_channels[chevron_number]

    def get_chevron_led(self, chevron_number):
        return self.led_channels[chevron_number]

    def get_stepper(self):
        return self.stepper

    @staticmethod
    def get_stepper_forward():
        return 1 # Forward

    @staticmethod
    def get_stepper_backward():
        return 2 # Backward

    @staticmethod
    def get_stepper_drive_mode(drive_mode): # pylint: disable=unused-argument
        return 2 # Double

    @staticmethod
    def init_spi_for_adc():
        pass

    @staticmethod
    def get_adc_by_channel():
        return 0

    @staticmethod
    def homing_supported():
        return False

    @staticmethod
    def get_homing_sensor_voltage():
        return 0

    def init_neopixels(self):
        self.neopixels = NeopixelSim(self.neopixel_led_count)
        #self.neopixels = neopixel.NeoPixel(self.neopixel_pin, self.neopixel_led_count, auto_write=False, brightness=0.61)

    def get_wormhole_pixels(self):
        return self.neopixels

    def get_wormhole_pixel_count(self):
        return self.neopixel_led_count
