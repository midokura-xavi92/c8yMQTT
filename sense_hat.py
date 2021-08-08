from collections import namedtuple
from random import randrange


class JoystickDummy:

    event = namedtuple("Event", ["action", "direction"])

    def get_events(self):
        yield event("up", "left")


class SenseHatDummy:

    stick = JoystickDummy()

    def get_temperature(self):
        return randrange(-20, 130)

    def get_humidity(self):
        return randrange(0, 98)

    def get_pressure(self):
        return randrange(100, 200)

    def get_accelerometer_raw(self):
        return {"x": randrange(-9, 9), "y": randrange(-9, 9), "z": randrange(-9, 9)}

    def get_orientation(self):
        return {
            "roll": randrange(-9, 9),
            "pitch": randrange(-9, 9),
            "yaw": randrange(-9, 9),
        }

    def show_message(self, msg):
        print("SenseHat shows", msg)

    def clear(self):
        pass
