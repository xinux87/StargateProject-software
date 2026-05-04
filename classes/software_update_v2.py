from version import VERSION as current_version

class SoftwareUpdateV2:

    def __init__(self, app):
        self.current_version = current_version

    def get_current_version(self):
        return self.current_version
