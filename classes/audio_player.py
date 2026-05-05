"""
Drop-in replacement for simpleaudio using aplay subprocess.
simpleaudio 1.0.4 segfaults on Debian 13 / Python 3.13 / aarch64.
"""
import subprocess


class WaveObject:

    def __init__(self, path):
        self._path = path

    @classmethod
    def from_wave_file(cls, path):
        return cls(str(path))

    def play(self):
        proc = subprocess.Popen(
            ['aplay', '-q', self._path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return PlayObject(proc)


class PlayObject:

    def __init__(self, proc):
        self._proc = proc

    def is_playing(self):
        return self._proc.poll() is None

    def stop(self):
        if self.is_playing():
            self._proc.terminate()

    def wait_done(self):
        self._proc.wait()
