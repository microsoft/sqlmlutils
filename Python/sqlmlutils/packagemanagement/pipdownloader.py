import os
import re
import requirements
import subprocess
import sys

from sqlmlutils import ConnectionInfo, SQLPythonExecutor
from sqlmlutils.packagemanagement import servermethods

class PipDownloader:

    def __init__(self, connection: ConnectionInfo, downloaddir: str, targetpackage: str):
        self._connection = connection
        self._downloaddir = downloaddir
        self._targetpackage = targetpackage
        server_info = SQLPythonExecutor(connection).execute_function_in_sql(servermethods.get_server_info)
        globals().update(server_info)

    def download(self):
        return self._download(True)

    def download_single(self) -> str:
        _, pkgsdownloaded = self._download(False)
        return pkgsdownloaded[0]

    def _download(self, withdependencies):
        # This command directs pip to download the target package, as well as all of its dependencies into
        # temporary_directory.
        commands = ["download", self._targetpackage, "--destination-dir", self._downloaddir, "--no-cache-dir"]
        if not withdependencies:
            commands.append("--no-dependencies")

        output, error = self._run_in_new_process(commands)
        
        pkgreqs = self._get_reqs_from_output(output)

        packagesdownloaded = [os.path.join(self._downloaddir, f) for f in os.listdir(self._downloaddir)
                              if os.path.isfile(os.path.join(self._downloaddir, f))]

        if len(packagesdownloaded) <= 0:
            raise RuntimeError("Failed to download any packages, pip returned error: " + error)
            
        return pkgreqs, packagesdownloaded

    def _run_in_new_process(self, commands):
        # We get the package requirements based on the print output of pip, which is stable across version 8-10.
        # TODO: get requirements in a more robust way (either through using pip internal code or rolling our own)
        download_script = os.path.join((os.path.dirname(os.path.realpath(__file__))), "download_script.py")
        exe_path = sys.executable if sys.executable is not None else "python"
        args = [exe_path, download_script,
                str(_patch_get_impl_version_info()), str(_patch_get_abbr_impl()),
                str(_patch_get_abi_tag()), str(_patch_get_platform()),
                ",".join(str(x) for x in commands)]

        with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as proc:
            output = proc.stdout.read()
            error = proc.stderr.read()

        return output.decode(), error.decode()

    @staticmethod
    def _get_reqs_from_output(pipoutput: str):
        # TODO: get requirements in a more robust way (either through using pip internal code or rolling our own)
        collectinglines = [line for line in pipoutput.splitlines() if "Collecting" in line]

        f = lambda unclean: \
            re.sub(r'\(.*\)', "", unclean.replace("Collecting ", "").strip())

        reqstr = "\n".join([f(line) for line in collectinglines])
        return list(requirements.parse(reqstr))


def _patch_get_impl_version_info():
    return globals()["impl_version_info"]


def _patch_get_abbr_impl():
    return globals()["abbr_impl"]


def _patch_get_abi_tag():
    return globals()["abi_tag"]


def _patch_get_platform():
    return globals()["platform"]

