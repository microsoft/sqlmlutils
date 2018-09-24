import sys
import io


class OutputCapture(io.StringIO):

    def write(self, txt):
        sys.__stdout__.write(txt)
        super().write(txt)
