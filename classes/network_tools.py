from ipaddress import ip_address
import socket
import netifaces

class NetworkTools:

    def __init__(self, log):

        self.log = log

    def get_ip(self, fqdn_or_ip):
        """
        This function takes a string as input and validates if the string is a valid IP address. If it is not a valid IP
        the function assumes it is a FQDN and tries to resolve the IP from the domain name. If this fails, it returns None
        :param fqdn_or_ip: A string of an IP or a FQDN
        :return: The IP address is returned as a string, or None is returned if it fails.
        """
        _ip_address = None
        try:
            _ip_address = ip_address(fqdn_or_ip)
            # print('yay, it is an IP')
        except ValueError:
            try:
                # print('NOPE, not an IP, getting IP from FQDN')
                _ip_address = socket.gethostbyname(fqdn_or_ip)
                # print('I found the IP:', ip)
            except ValueError:
                pass
        except Exception: # pylint: disable=broad-except
            self.log.log(f"Unable to determine IP address '{fqdn_or_ip}'")
            _ip_address = None
        return str(_ip_address)

    def get_local_ip(self):
        my_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            # doesn't even have to be reachable
            my_sock.connect(('8.8.8.8', 1))
            ret = my_sock.getsockname()[0]
        except socket.error:
            ret = '127.0.0.1'
        finally:
            my_sock.close()
        return ret

    def get_subspace_ip(self, subspace_only = False):
        # Try to get the IP from subspace
        subspace = self.get_ip_by_interface_list( ['subspace'] )
        if subspace:
            return subspace

        if not subspace_only:
            lan = self.get_ip_by_interface_list( [ 'wlan0', 'eth0', 'en0', 'en1' ] )
            if lan:
                return lan

        return None

    def get_ip_by_interface_list(self, interfaces):

        # Try to get the IP from each of the interfaces, in order. Return the first one.
        for interface in interfaces:
            result = self.get_ip_address_by_interface(interface)
            if result:
                return result

        return None

    def get_ip_address_by_interface(self, interface_name):
        try:
            server_ip = netifaces.ifaddresses(interface_name)[2][0]['addr']
            if ip_address(server_ip):
                return server_ip
            return False
        except (KeyError, ValueError) as _ex:
            self.log.log(f'ERROR getting {interface_name} IP: {_ex}', True)
            return False
