import sys
import os
from datetime import datetime
import threading

# pylint: disable=too-few-public-methods

class AncientsLogBook:

    def __init__(self, base_path, log_file, print_to_console = True):

        self.print_to_console = print_to_console
        self.gate_log = log_file
        self.log_dir = base_path + "/logs" #No trailing slash
        self._print_lock = threading.Lock()
        self._rotate_log()

    def _rotate_log(self, max_bytes=2 * 1024 * 1024):
        log_path = self.log_dir + "/" + self.gate_log
        if os.path.exists(log_path) and os.path.getsize(log_path) > max_bytes:
            backup = log_path + ".1"
            if os.path.exists(backup):
                os.remove(backup)
            os.rename(log_path, backup)

    def log(self, msg, print_to_console_override = False):
        """
        This functions logs the string_for_logging to the end of file.
        :param msg: the entry for the log, as a string. The timestamp will be prepended automatically.
        :return: Nothing is returned.
        """

        with open(self.log_dir +"/"+ self.gate_log, 'a+', encoding="utf8") as log_file:
            timestamp = datetime.now().replace(microsecond=0)
            log_line = f'\n[{timestamp}]\t{msg}'
            log_file.write(log_line)

        if self.print_to_console and not print_to_console_override:
            with self._print_lock:
                print(log_line, end='\r')
                sys.stdout.flush()
