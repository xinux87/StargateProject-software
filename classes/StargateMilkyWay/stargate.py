from threading import Thread, Event
from time import time, sleep
from random import randrange

from stargate_config import StargateConfig
from symbol_manager import StargateSymbolManager
from chevrons import ChevronManager
from dialers import Dialer
from keyboard_manager import KeyboardManager
from symbol_ring import SymbolRing
from stargate_address_manager import StargateAddressManager
from wormhole_manager import WormholeManager
from dialing_log import DialingLog

class Stargate:
    """
    This is the class to create the stargate object itself.
    """
    def __init__(self, app):

        self.app = app
        self.log = app.log
        self.cfg = app.cfg
        self.audio = app.audio
        self.electronics = app.electronics
        self.base_path = app.base_path
        self.net_tools = app.net_tools
        self.schedule = app.schedule
        self.galaxy = app.galaxy
        self.galaxy_path = app.galaxy_path

        self.log.log('Initializing Milky Way Stargate Software')

        # Retrieve the configurations
        self.inactivity_timeout = self.cfg.get("dialing_timeout")

        # Initialize the state variables
        self.running = True
        self.address_buffer_outgoing = [] #Storage buffer for dialed outgoing address
        self.address_buffer_incoming = [] #Storage buffer for dialed incoming address
        self.last_activity_time = None # A variable to store the last user input time
        self.centre_button_outgoing = False #A variable for the state of the centre button, outgoing.
        self.centre_button_incoming = False #A variable for the state of the centre button, incoming.
        self.locked_chevrons_outgoing = 0 # The current number of locked outgoing chevrons
        self.locked_chevrons_incoming = 0 # The current number of locked outgoing chevrons
        self.wormhole_active = False # The state of the wormhole.
        self.black_hole = False # Did we dial the black hole?
        self.connected_planet_name = None
        self.dhd_test = False

        # Load silence_mode from persistent store
        self.silence_store = StargateConfig(self.base_path, "silence_mode", self.galaxy_path)
        self.silence_store.set_log(self.log)
        self.silence_store.load()
        self.silence_mode = self.silence_store.get('silence_mode')

        # Lamp mode state (LED strip used as a plain RGB light or animated)
        self.lamp_mode = False
        self.lamp_color = (255, 255, 255)  # RGB
        self.lamp_brightness = 255         # 0-255
        self.lamp_animation = 'static'     # animation id
        self.lamp_animation_active = False
        self._lamp_animation_thread = None

        ### Set up the needed classes and make them ready to use ###
        self.symbol_manager = StargateSymbolManager(self.galaxy_path)
        self.addr_manager = StargateAddressManager(self)
        self.chevrons = ChevronManager(self)
        self.ring = SymbolRing(self)
        self.dialer = Dialer(self) # A "Dialer" is either a Keyboard or DHDv2
        self.keyboard = KeyboardManager(self, app.is_daemon)
        self.wh_manager = WormholeManager(self)
        self.wh_manager.initialize_animation_manager()
        self.dialing_log = DialingLog(self)

        ### Notify that the Stargate is ready
        self.audio.play_random_clip("startup")
        self.log.log('The Stargate is started and ready!')

    def initialize_gate_state_vars(self):
        """
        This method resets the state variables to "gate idle"
        :return:
        """
        # Reset/initialize the state variables and address buffers
        self.address_buffer_outgoing = [] #Storage buffer for dialed outgoing address
        self.address_buffer_incoming = [] #Storage buffer for dialed incoming address
        self.last_activity_time = None # A variable to store the last user input time
        self.centre_button_outgoing = False #A variable for the state of the centre button, outgoing.
        self.centre_button_incoming = False #A variable for the state of the centre button, incoming.
        self.locked_chevrons_outgoing = 0 # The current number of locked outgoing chevrons
        self.locked_chevrons_incoming = 0 # The current number of locked outgoing chevrons
        self.wormhole_active = False # The state of the wormhole.
        self.black_hole = False # Did we dial the black hole?
        self.connected_planet_name = None

    def update(self):
        """
        This is the main method to keep the stargate running and make decisions based on the manipulated objects variables.
        There are basically two main phases, the dialing phase and the wormhole phase.
        :return: Nothing is returned.
        """
        while self.running: # If we have not aborted

            # Auto-exit lamp mode if any Stargate activity is detected
            if self.lamp_mode and (
                len(self.address_buffer_outgoing) > 0 or
                len(self.address_buffer_incoming) > 0 or
                self.wormhole_active
            ):
                self._stop_lamp_animation()
                self.lamp_mode = False
                self.wh_manager.animation_manager.clear_wormhole()
                self.log.log('Lamp mode: auto-OFF (Stargate activity detected)')

            ### The Dialing phase###
            if not self.wormhole_active and self.running and not self.lamp_mode: # If we are in the dialing phase

                ## Outgoing dialing ##
                self.outgoing_dialing()

                ## Incoming dialing ##
                self.incoming_dialing()

                ## Establishing wormhole ##
                self.establishing_wormhole()

                ### Check for inactivity ###
                # If there are something in the buffers and no activity for 1 minute while dialing.
                # TODO: Use Schedule
                if self.inactivity( self.inactivity_timeout ):
                    self.log.log('Inactivity detected, aborting.')
                    self.shutdown()

            ### The wormhole phase ###
            elif self.wormhole_active: # If wormhole
                self.ring.release() # Release the stepper motor.
                self.wh_manager.establish_wormhole() # This will establish the wormhole and keep it running until self.wormhole_active is False
                #When the wormhole is no longer running
                self.shutdown(cancel_sound=False)

            self.schedule.run_pending() # Run any scheduled items

            sleep(0.1) # Give the CPU a break (and yield to other threads)

        # When the stargate is no longer running.
        self.shutdown(cancel_sound=False)


    def outgoing_dialing(self):
        """
        This method handles the outgoing dialing of the stargate. It's kept in it's own method so not to clutter up the update method too much.
        :return: Nothing is returned
        """
        if len(self.address_buffer_outgoing) > self.locked_chevrons_outgoing:
            if self.silence_mode:
                # Interruptible delay: exits early if silence mode is turned off mid-dial
                elapsed = 0.0
                delay = self.cfg.get("silence_mode_dial_delay")
                while elapsed < delay and self.silence_mode and self.running:
                    sleep(0.05)
                    elapsed += 0.05
            else:
                self.ring.move_symbol_to_chevron(self.address_buffer_outgoing[self.locked_chevrons_outgoing], self.locked_chevrons_outgoing + 1)  # Dial the symbol
            self.locked_chevrons_outgoing += 1  # Increment the locked chevrons variable.

            # If the gate shutdown requested, play the stop-dialing sound, and stop doing things.
            if not self.running:
                self.shutdown(cancel_sound=False, wormhole_fail_sound=True)
                sleep(0.5) # Time to allow the wormhole_fail_sound to finish
                return

            try:
                self.chevrons.get(self.locked_chevrons_outgoing).cycle_outgoing()  # Do the chevron locking thing.
            except KeyError:  # If we dialed more chevrons than the stargate can handle.
                pass  # Just pass without activating a chevron.

            try:
                self.log.log(f'Chevron {self.locked_chevrons_outgoing} locked with symbol: {self.address_buffer_outgoing[self.locked_chevrons_outgoing - 1]}')
            except IndexError:
                pass
            self.last_activity_time = time()  # update the last_activity_time

    def incoming_dialing(self):
        """
        This method handles the incoming dialing of the stargate. It's kept in it's own method so not to clutter up the update method too much.
        :return: Nothing is returned
        """

        # If there are dialed incoming symbols that are not yet locked and we are currently not dialing out.
        if len(self.address_buffer_incoming) > self.locked_chevrons_incoming and len(self.address_buffer_outgoing) == 0:

            # If there are more than one unlocked symbol, add a short delay to avoid locking both symbols at once.
            if len(self.address_buffer_incoming) > self.locked_chevrons_incoming + 1:
                delay = randrange(1, 800) / 100  # Add a delay with some randomness
            else:
                delay = 0

            # If we are still receiving the correct address to match the local stargate:
            buffer_first_6 = self.address_buffer_incoming[0:min(len(self.address_buffer_incoming), 6)] # get up to 6 symbols off incoming buffer
            local_first_6 = self.addr_manager.get_book().get_local_address()[0:min(len(self.address_buffer_incoming), 6)] # get up to 6 symbols off the local address_buffer_incoming
            loopback_first_6 = self.addr_manager.get_book().get_local_loopback_address()[0:min(len(self.address_buffer_incoming), 6)] # get up to 6 symbols off the loopback local address

            # If the incoming address buffer matches our routable or unroutable local address, lock it.
            if buffer_first_6 in (local_first_6, loopback_first_6):
                self.log.log("Address matching. Incoming Buffer: " + str(self.address_buffer_incoming))

                self.locked_chevrons_incoming += 1  # Increment the locked chevrons variable.
                try:
                    self.chevrons.get(self.locked_chevrons_incoming).incoming_on()  # Do the chevron locking thing.
                except KeyError:  # If we dialed more chevrons than the stargate can handle.
                    pass  # Just pass without activating a chevron.

                # Play the audio clip for incoming wormhole for the first chevron
                if self.locked_chevrons_incoming == 1 and not self.silence_mode:
                    self.audio.play_random_clip("IncomingWormhole")

                self.last_activity_time = time()  # update the last_activity_time

                # Do the logging
                self.log.log(f'Incoming: Chevron {self.locked_chevrons_incoming} locked with symbol {self.address_buffer_incoming[self.locked_chevrons_incoming - 1]}')

                sleep(delay)  # if there's a delay, use it.
            else:
                self.log.log("Address is not a match for this gate")

    def get_connected_planet_name(self):

        if self.wormhole_active == 'outgoing':
            return self.addr_manager.get_planet_name_by_address(self.address_buffer_outgoing)
        # Not connected (or incoming with unknown origin)
        return False

    def establishing_wormhole(self):
        """
        This is the method that decides if we are to establish a wormhole or not
        :return: Nothing is returned, But the self.wormhole_active variable is changed if we can establish a wormhole.
        """
        ### Establishing wormhole ###
        ## Outgoing wormhole##
        # If the centre_button_outgoing is active and all dialed symbols are locked.
        if self.centre_button_outgoing and (0 < len(self.address_buffer_outgoing) == self.locked_chevrons_outgoing):

            # Try to establish a wormhole
            if self.possible_to_establish_wormhole():

                self.ring.release() # Release the stepper to prevent overheating

                # Update the state variables
                self.wormhole_active = 'outgoing'
                self.connected_planet_name = self.get_connected_planet_name()

                # Log some stuff
                self.log.log('Valid address is locked')
                self.log.log(f'OUTGOING Wormhole to {self.connected_planet_name} established')

                # Log the connection!
                self.dialing_log.established_outbound(self.address_buffer_outgoing)

                # Check if we dialed a black hole planet
                if self.addr_manager.get_book().get_entry_by_address(self.address_buffer_outgoing[0:-1])['is_black_hole']:
                    self.log.log("Oh no! It's the black hole planet!")
                    self.black_hole = True
            else:
                # Log the dialing failure
                self.dialing_log.dialing_fail(self.address_buffer_outgoing)
                self.shutdown(cancel_sound=False, wormhole_fail_sound=True)

        ## Incoming wormhole ##
        # If the centre_button_incoming is active and all dialed symbols are locked.
        elif self.centre_button_incoming and 0 < len(self.address_buffer_incoming) == self.locked_chevrons_incoming:
            # If the incoming wormhole matches the local address
            if self.address_buffer_incoming[0:-1] == self.addr_manager.get_book().get_local_address() or \
                self.address_buffer_incoming[0:-1] == self.addr_manager.get_book().get_local_loopback_address():
                # Update some state variables
                self.wormhole_active = 'incoming'  # Set the wormhole state to activate the wormhole.
                self.connected_planet_name = self.get_connected_planet_name()
                self.dialer.hardware.set_center_on() # Activate the centre_button light

                self.log.log('Incoming address is a match!')
                self.log.log(f'INCOMING Wormhole from {self.connected_planet_name} established')

                # Log the connection!
                # TODO: hook this up!
                #self.dialing_log.established_inbound( self.inbound_dialer)

            else:
                self.log.log('Incoming address is NOT a match to Local Gate Address!')
                self.shutdown(cancel_sound=False, wormhole_fail_sound=True)


    def shutdown(self, cancel_sound=True, wormhole_fail_sound=False):
        """
        This method shuts down and resets the Stargate.
        :return:
        """

        self.log.log('Shutting down the gate...')

        # Play the cancel sound
        if cancel_sound and not self.silence_mode:
            self.audio.sound_start('dialing_cancel')

        # Play the wormhole fail sound
        if wormhole_fail_sound and not self.silence_mode:
            self.audio.sound_start('dialing_fail')

        # Turn off the chevrons
        self.chevrons.all_off()

        # Turn off the DHD lights
        self.dialer.hardware.clear_lights()

        # Release the stepper motor.
        self.ring.release()

        # Put the gate back in to an idle state
        self.initialize_gate_state_vars()

        self.dialing_log.shutdown()

    def inactivity(self, seconds):
        """
        This functions checks if there has been more than the variable seconds of inactivity:
        :param seconds: The number of seconds of allowed inactivity
        :return: True if inactivity is detected, False if not
        """

        # TODO: Use schedule

        if not self.wormhole_active: #If we are in the dialing phase
            if self.last_activity_time: #If the variable is not None
                if (len(self.address_buffer_incoming) > 0) or (len(self.address_buffer_outgoing) > 0): # If there are something in the buffers
                    if (time() - self.last_activity_time) > seconds:
                        return True
        return False

    def possible_to_establish_wormhole(self):
        if ( len(self.address_buffer_outgoing) > 0 and self.addr_manager.valid_planet(self.address_buffer_outgoing) or \
            len(self.address_buffer_incoming) > 0 and self.addr_manager.valid_planet(self.address_buffer_incoming) ):
            return True
        return False

    def set_silence_mode(self, value: bool):
        self.silence_mode = value
        self.silence_store.set_non_persistent('silence_mode', value)
        self.silence_store.save()
        self.log.log(f'Silence mode: {"ON" if value else "OFF"}')

    LAMP_ANIMATIONS = [
        {"id": "static",     "name": "Static Color"},
        {"id": "wormhole",   "name": "Wormhole Effect"},
        {"id": "black_hole", "name": "Black Hole"},
        {"id": "kawoosh",    "name": "Kawoosh Loop"},
    ]
    LAMP_ANIMATION_IDS = {a["id"] for a in LAMP_ANIMATIONS}

    def set_lamp_mode(self, state: bool, color=None, brightness=None, animation=None):
        if state:
            # Stop any active wormhole or dialing sequence cleanly
            if self.wormhole_active:
                self.wormhole_active = False
                sleep(0.3)
            self._stop_lamp_animation()
            self.shutdown(cancel_sound=False, wormhole_fail_sound=False)

            if color is not None:
                self.lamp_color = tuple(int(c) for c in color)
            if brightness is not None:
                self.lamp_brightness = max(0, min(255, int(brightness)))
            if animation is not None and animation in self.LAMP_ANIMATION_IDS:
                self.lamp_animation = animation

            self.lamp_mode = True
            if self.lamp_animation == 'static':
                self._apply_lamp()
            else:
                self._start_lamp_animation()
        else:
            self._stop_lamp_animation()
            self.lamp_mode = False
            self.wh_manager.animation_manager.clear_wormhole()
            self.log.log('Lamp mode: OFF')

    def lamp_set(self, color=None, brightness=None, animation=None):
        if color is not None:
            self.lamp_color = tuple(int(c) for c in color)
        if brightness is not None:
            self.lamp_brightness = max(0, min(255, int(brightness)))

        animation_changed = animation is not None and animation in self.LAMP_ANIMATION_IDS and animation != self.lamp_animation
        if animation_changed:
            self.lamp_animation = animation
            if self.lamp_mode:
                self._stop_lamp_animation()
                if self.lamp_animation == 'static':
                    self._apply_lamp()
                else:
                    self._start_lamp_animation()
        elif self.lamp_mode:
            if self.lamp_animation == 'static':
                self._apply_lamp()

    def _apply_lamp(self):
        pixels = self.wh_manager.animation_manager.pixels
        tot_leds = self.wh_manager.animation_manager.tot_leds
        r, g, b = self.lamp_color
        scale = self.lamp_brightness / 255.0
        color = (int(r * scale), int(g * scale), int(b * scale))
        pattern = [color] * tot_leds
        self.wh_manager.animation_manager.set_wormhole_pattern(pattern)
        self.log.log(f'Lamp mode: ON — color={self.lamp_color}, brightness={self.lamp_brightness}, animation={self.lamp_animation}')

    def _start_lamp_animation(self):
        self.lamp_animation_active = True
        t = Thread(target=self._run_lamp_animation, daemon=True)
        self._lamp_animation_thread = t
        t.start()

    def _stop_lamp_animation(self):
        self.lamp_animation_active = False
        t = self._lamp_animation_thread
        if t is not None and t.is_alive():
            t.join(timeout=3)
        self._lamp_animation_thread = None

    def _run_lamp_animation(self):
        mgr = self.wh_manager.animation_manager
        anim = self.lamp_animation
        self.log.log(f'Lamp animation thread started: {anim}')
        while self.lamp_animation_active and self.lamp_mode:
            if anim == 'wormhole':
                mgr.do_random_transitions(is_black_hole=False)
            elif anim == 'black_hole':
                mgr.do_random_transitions(is_black_hole=True)
            elif anim == 'kawoosh':
                mgr.animate_kawoosh()
                sleep(1.0)
            else:
                break
        self.log.log(f'Lamp animation thread stopped: {anim}')
