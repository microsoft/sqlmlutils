class ClassA:

    def __init__(self, val):
        self._val = val

    @property
    def val(self):
        return self._val