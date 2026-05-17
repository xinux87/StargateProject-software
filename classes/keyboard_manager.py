import sys
from threading import Thread
import tty
import termios

class KeyboardManager:

    def __init__(self, stargate, is_daemon):

        self.stargate = stargate
        self.is_daemon = is_daemon
        self.log = stargate.log
        self.cfg = stargate.cfg
        self.audio = stargate.audio
        self.addr_manager = stargate.addr_manager
        self.address_book = stargate.addr_manager.get_book()
        self.symbol_manager = stargate.symbol_manager

        self.dhd_test_enable = False
        self.dhd_test_active_buttons = []
        self.center_button_key = "A"

        if is_daemon:
            self.keyboard_direct_thread_start()
        else:
            self.stdin_thread_start()

    @staticmethod
    def get_abort_characters():
        # If these symbols are entered, the gate will shutdown
        return [ '-', '\x03' ]  # '\x03' == Ctrl-C

    def stdin_thread_start(self):
        ## Create a background thread that runs in parallel and asks for user inputs from the DHD or keyboard.
        self.ask_for_input_thread = Thread(target=self.thread_stdin, args=([self.stargate]), daemon=True)
        self.ask_for_input_thread.start()

    @staticmethod
    def block_for_stdin():
        """
        This helper function stops the program (thread) and waits for a single keypress on STDIN.
        :return: The pressed key is returned.
        """

        file_desc = sys.stdin.fileno()
        old_settings = termios.tcgetattr(file_desc)
        try:
            tty.setraw(sys.stdin.fileno())
            char = sys.stdin.read(1)
        finally:
            termios.tcsetattr(file_desc, termios.TCSADRAIN, old_settings)
        return char

    def thread_stdin(self, stargate):
        """
        This function takes the stargate as input and listens for user input (from the DHD or keyboard).
        This function is run in parallel in its own thread.
        :return: Nothing is returned, but the stargate is manipulated.
        """

        stargate.log.log("Listening for input from the DHD/Keyboard on STDIN. You can abort with the '-' key.")
        while stargate.running:
            self.keypress_handler( self.block_for_stdin() ) # Blocks the thread until a character is subspace_client_server_thread

    def keyboard_direct_thread_start(self):
        ## Create a background thread that runs in parallel and asks for user inputs from the DHD or keyboard.
        self.ask_for_input_thread = Thread(target=self.thread_keyboard_direct, args=([self.stargate]), daemon=True)
        self.ask_for_input_thread.start()

    def thread_keyboard_direct(self, stargate):
        """
        Lee input del teclado físico o DHD (HID) via evdev / /dev/input.
        Soporta hotplug: detecta conexión/desconexión sin reiniciar el servicio.
        """
        try:
            # pylint: disable-next=import-outside-toplevel
            import evdev
            from evdev import ecodes  # pylint: disable=import-outside-toplevel
            import selectors  # pylint: disable=import-outside-toplevel

            keycode_map = self._build_evdev_keycode_map()

            sel = selectors.DefaultSelector()
            registered_paths = set()  # paths de /dev/input actualmente en el selector

            def _register_keyboards():
                added = 0
                for path in evdev.list_devices():
                    if path in registered_paths:
                        continue
                    try:
                        dev = evdev.InputDevice(path)
                        caps = dev.capabilities()
                        key_codes = set(caps.get(ecodes.EV_KEY, []))
                        if ecodes.KEY_A in key_codes and ecodes.KEY_1 in key_codes:
                            sel.register(dev, selectors.EVENT_READ)
                            registered_paths.add(path)
                            stargate.log.log(f'KEYBOARD: Dispositivo conectado: {dev.name} ({path})')
                            added += 1
                        else:
                            dev.close()
                    except OSError:
                        pass
                return added

            # Escaneo inicial
            if _register_keyboards() == 0:
                stargate.log.log('KEYBOARD: No se encontró ningún dispositivo teclado al arrancar. Esperando hotplug...')

            stargate.log.log("Listening for input from the DHD/Keyboard via direct input. You can abort with the '-' key.")

            left_shift = False
            right_shift = False
            scan_counter = 0
            RESCAN_EVERY = 5  # iteraciones (≈ 5 s con timeout=1.0)

            while stargate.running:
                # Re-scan periódico para detectar nuevos dispositivos (hotplug)
                if scan_counter >= RESCAN_EVERY:
                    _register_keyboards()
                    scan_counter = 0
                scan_counter += 1

                for key, _ in sel.select(timeout=1.0):
                    dev = key.fileobj
                    try:
                        for event in dev.read():
                            if event.type != ecodes.EV_KEY:
                                continue
                            # Rastrear shift
                            if event.code == ecodes.KEY_LEFTSHIFT:
                                left_shift = (event.value != 0)
                                continue
                            if event.code == ecodes.KEY_RIGHTSHIFT:
                                right_shift = (event.value != 0)
                                continue
                            # Solo key_down (value=1), ignorar key_up(0) y key_hold(2)
                            if event.value != 1:
                                continue
                            char = keycode_map.get((event.code, left_shift or right_shift))
                            if char is not None:
                                self.keypress_handler(char)
                    except OSError:
                        stargate.log.log(f'KEYBOARD: Dispositivo desconectado: {dev.name} ({dev.path})')
                        registered_paths.discard(dev.path)
                        sel.unregister(dev)
                        try:
                            dev.close()
                        except OSError:
                            pass

            sel.close()

        except Exception as ex:  # pylint: disable=broad-except
            stargate.log.log(f'KEYBOARD ERROR: evdev thread falló: {ex}')
            stargate.log.log('El input del teclado NO funcionará. Verificar que evdev esté instalado.')

    @staticmethod
    def _build_evdev_keycode_map():
        """
        Retorna dict: (keycode_int, shift_held: bool) -> char_string
        Cubre todas las teclas definidas en StargateSymbolManager.
        """
        # pylint: disable-next=import-outside-toplevel
        from evdev import ecodes

        result = {}

        # Letras: sin shift -> minúscula, con shift -> mayúscula
        for letter in 'abcdefghijklmnopqrstuvwxyz':
            code = getattr(ecodes, f'KEY_{letter.upper()}', None)
            if code is not None:
                result[(code, False)] = letter
                result[(code, True)]  = letter.upper()

        # Dígitos 0-9 (shift+dígito produce !@#... que no se usa aquí)
        digit_map = {
            '1': ecodes.KEY_1, '2': ecodes.KEY_2, '3': ecodes.KEY_3,
            '4': ecodes.KEY_4, '5': ecodes.KEY_5, '6': ecodes.KEY_6,
            '7': ecodes.KEY_7, '8': ecodes.KEY_8, '9': ecodes.KEY_9,
            '0': ecodes.KEY_0,
        }
        for char, code in digit_map.items():
            result[(code, False)] = char
            result[(code, True)]  = char

        # Carácter de abort
        result[(ecodes.KEY_MINUS, False)] = '-'

        return result

    def enable_dhd_test( self, enable ):
        if enable:
            self.stargate.shutdown()
            self.dhd_test_enable = True
        else:
            self.dhd_test_enable = False
            self.stargate.dialer.hardware.clear_lights()

        self.dhd_test_active_buttons = []

    def handle_dhd_test(self, key):
        # Handle test mode here
        symbol_number = None
        try:
            symbol_number = self.symbol_manager.get_symbol_key_map()[key]
            self.log.log(f'DHD Test: Pressed Key {key} --> Symbol {symbol_number}')
        except KeyError:
            if key == self.center_button_key:
                symbol_number = 0
                self.log.log(f'DHD Test: Pressed Center Button {key} --> Symbol 0')
            else:
                self.log.log(f'DHD Test: Key NOT RECOGNIZED {key}')
                return

        if symbol_number not in self.dhd_test_active_buttons:
            self.dhd_test_active_buttons.append(symbol_number)
            if symbol_number == 0:
                self.stargate.dialer.hardware.set_pixel(symbol_number, 255, 0, 0) # TODO: Use colors in config
                self.stargate.dialer.hardware.latch()
            else:
                self.stargate.dialer.hardware.set_pixel(symbol_number, 250, 117, 0) # TODO: Use colors in config
                self.stargate.dialer.hardware.latch()
        else:
            self.dhd_test_active_buttons.remove(symbol_number)
            self.stargate.dialer.hardware.clear_pixel(symbol_number)
            self.stargate.dialer.hardware.latch()

    def keypress_handler( self, key ):
        """
        This function takes a keypress and interprets it's meaning for the Stargate.
        :return: Nothing is returned, but the stargate is manipulated.
        """

        if self.dhd_test_enable:
            self.handle_dhd_test( key )
            return

        ## If the user inputs one of the abort characters, stop the software. Not possible from the DHD.
        if key in self.get_abort_characters():
            self.log.log("Abort Requested: Shutting down any active wormholes, stopping the gate.")
            self.stargate.wormhole_active = False # Shutdown any open wormholes (particularly if turned on via web interface)
            self.stargate.running = False  # Stop the stargate object from running.
            return

        # Center Button
        if key == self.center_button_key:
            symbol_number = 'centre_button_outgoing'
            self.log.log(f'key: {key} -> symbol: {symbol_number} CENTER')
            self.queue_center_button()
            return

        # Try to convert other key presses to symbol_number
        try:
            symbol_number = self.symbol_manager.get_symbol_key_map()[key]
            self.queue_symbol(symbol_number)
            return
        except KeyError:
            # The key pressed is not a symbol
            self.log.log(f'Unknown key: {key}')

    def queue_symbol(self, symbol_number):
        self.audio.play_random_clip("DHD")
        if symbol_number != 'unknown' and symbol_number not in self.stargate.address_buffer_outgoing:
            # If we have not yet activated the centre_button
            if not (self.stargate.centre_button_outgoing or self.stargate.centre_button_incoming):
                self.stargate.dialer.hardware.set_symbol_on( symbol_number ) # Light this symbol on the DHD

                # Append the symbol to the outgoing address buffer
                self.stargate.address_buffer_outgoing.append(symbol_number)
                self.log.log(f'address_buffer_outgoing: {self.stargate.address_buffer_outgoing}') # Log the address_buffer

    def queue_center_button(self):
        self.audio.play_random_clip("DHD")
        # If we are dialing
        if len(self.stargate.address_buffer_outgoing) > 0 and not self.stargate.wormhole_active:
            self.stargate.centre_button_outgoing = True
            self.stargate.dialer.hardware.set_center_on() # Activate the centre_button_outgoing light
        # If an outgoing wormhole is established
        if self.stargate.wormhole_active == 'outgoing':
            if not self.stargate.black_hole:
                self.stargate.wormhole_active = False
