# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import io
import os
import subprocess
import tempfile
from contextlib import redirect_stdout

import pytest

import sqlmlutils
from sqlmlutils import SQLPackageManager, SQLPythonExecutor
from package_helper_functions import _get_sql_package_table, _get_package_names_list
from sqlmlutils.packagemanagement.scope import Scope
from sqlmlutils.packagemanagement.pipdownloader import PipDownloader

from conftest import connection

path_to_packages = os.path.join((os.path.dirname(os.path.realpath(__file__))), "scripts", "test_packages")
_SUCCESS_TOKEN = "SUCCESS"

pyexecutor = SQLPythonExecutor(connection)
pkgmanager = SQLPackageManager(connection)

originals = _get_sql_package_table(connection)

def check_package(package_name: str, exists: bool, class_to_check: str = ""):
    if exists:
        themodule = __import__(package_name)
        assert themodule is not None
        assert getattr(themodule, class_to_check) is not None
    else:
        import pytest
        with pytest.raises(Exception):
            __import__(package_name)


def _execute_sql(script: str) -> bool:
    tmpfile = tempfile.NamedTemporaryFile(delete=False)
    tmpfile.write(script.encode())
    tmpfile.close()
    command = ["sqlcmd", "-d", "AirlineTestDB", "-i", tmpfile.name]
    try:
        output = subprocess.check_output(command, stderr=subprocess.STDOUT, shell=True).decode()
        return _SUCCESS_TOKEN in output
    finally:
        os.remove(tmpfile.name)


def _drop(package_name: str, ddl_name: str):
    pkgmanager.uninstall(package_name)
    pyexecutor.execute_function_in_sql(check_package, package_name=package_name, exists=False)


def _create(module_name: str, package_file: str, class_to_check: str, drop: bool = True):
    pyexecutor.execute_function_in_sql(check_package, package_name=module_name, exists=False)
    pkgmanager.install(package_file)
    pyexecutor.execute_function_in_sql(check_package, package_name=module_name, exists=True, class_to_check=class_to_check)
    if drop:
        _drop(package_name=module_name, ddl_name=module_name)


def _remove_all_new_packages(manager):
    libs = {dic['external_library_id']: (dic['name'], dic['scope']) for dic in _get_sql_package_table(connection)}
    original_libs = {dic['external_library_id']: (dic['name'], dic['scope']) for dic in originals}

    for lib in libs:
        pkg, sc = libs[lib]
        if lib not in original_libs:
            print("uninstalling" + str(lib))
            if sc:
                manager.uninstall(pkg, scope=Scope.private_scope())
            else:
                manager.uninstall(pkg, scope=Scope.public_scope())
        else:
            if sc != original_libs[lib][1]:
                if sc:
                    manager.uninstall(pkg, scope=Scope.private_scope())
                else:
                    manager.uninstall(pkg, scope=Scope.public_scope())


packages = ["absl-py==0.1.13", "astor==0.6.2", "bleach==1.5.0", "cryptography==2.2.2",
            "html5lib==1.0.1", "Markdown==2.6.11", "numpy==1.14.3", "termcolor==1.1.0", "webencodings==0.5.1"]

for package in packages:
    pipdownloader = PipDownloader(connection, path_to_packages, package)
    pipdownloader.download_single()

def test_install_basic_zip_package():
    package = os.path.join(path_to_packages, "testpackageA-0.0.1.zip")
    module_name = "testpackageA"

    _remove_all_new_packages(pkgmanager)

    _create(module_name=module_name, package_file=package, class_to_check="ClassA")


def test_install_basic_zip_package_different_name():
    package = os.path.join(path_to_packages, "testpackageA-0.0.1.zip")
    module_name = "testpackageA"

    _remove_all_new_packages(pkgmanager)
    _create(module_name=module_name, package_file=package, class_to_check="ClassA")


def test_install_whl_files():
    packages = ["webencodings-0.5.1-py2.py3-none-any.whl", "html5lib-1.0.1-py2.py3-none-any.whl",
                "astor-0.6.2-py2.py3-none-any.whl"]
    module_names = ["webencodings",  "html5lib", "astor"]
    classes_to_check = ["LABELS",  "parse", "code_gen"]

    _remove_all_new_packages(pkgmanager)

    for package, module, class_to_check in zip(packages, module_names, classes_to_check):
        full_package = os.path.join(path_to_packages, package)
        _create(module_name=module, package_file=full_package, class_to_check=class_to_check, drop=False)

    for name in module_names:
        _drop(package_name=name, ddl_name=name)


def test_install_targz_files():
    packages = ["termcolor-1.1.0.tar.gz"]
    module_names = ["termcolor"]
    ddl_names = ["termcolor"]
    classes_to_check = ["colored"]

    _remove_all_new_packages(pkgmanager)

    for package, module, ddl_name, class_to_check in zip(packages, module_names, ddl_names, classes_to_check):
        full_package = os.path.join(path_to_packages, package)
        _create(module_name=module, package_file=full_package, class_to_check=class_to_check)


def test_install_bad_package_badzipfile():

    _remove_all_new_packages(pkgmanager)

    with tempfile.TemporaryDirectory() as temporary_directory:
        badpackagefile = os.path.join(temporary_directory, "badpackageA-0.0.1.zip")
        with open(badpackagefile, "w") as f:
            f.write("asdasdasdascsacsadsadas")
        with pytest.raises(Exception):
            pkgmanager.install(badpackagefile)

        assert "badpackageA" not in _get_package_names_list(connection)

        query = """
declare @val int;
set @val = (select count(*) from sys.external_libraries where name='badpackageA')
if @val = 0
    print('{}')
""".format(_SUCCESS_TOKEN)

        assert _execute_sql(query)


def test_package_already_exists_on_sql_table():

    _remove_all_new_packages(pkgmanager)

    package = os.path.join(path_to_packages, "testpackageA-0.0.1.zip")
    pkgmanager.install(package)

    # Without upgrade
    output = io.StringIO()
    with redirect_stdout(output):
        pkgmanager.install(package, upgrade=False)
    assert "exists on server. Set upgrade to True to force upgrade." in output.getvalue()

    # With upgrade
    package = os.path.join(path_to_packages, "testpackageA-0.0.2.zip")
    pkgmanager.install(package, upgrade=True)

    def check_version():
        import testpackageA
        return testpackageA.__version__

    version = pyexecutor.execute_function_in_sql(check_version)
    assert version == "0.0.2"

    pkgmanager.uninstall("testpackageA")


def test_upgrade_parameter():

    _remove_all_new_packages(pkgmanager)

    # Get sql packages
    originalsqlpkgs = _get_sql_package_table(connection)

    pkg = os.path.join(path_to_packages, "cryptography-2.2.2-cp35-cp35m-win_amd64.whl")

    output = io.StringIO()
    with redirect_stdout(output):
        pkgmanager.install(pkg, upgrade=False)
    assert "exists on server. Set upgrade to True to force upgrade." in output.getvalue()

    # Assert no additional packages were installed

    sqlpkgs = _get_sql_package_table(connection)
    assert len(sqlpkgs) == len(originalsqlpkgs)

    #################

    def check_version():
        import cryptography as cp
        return cp.__version__

    oldversion = pyexecutor.execute_function_in_sql(check_version)

    pkgmanager.install(pkg, upgrade=True)

    sqlpkgs = _get_sql_package_table(connection)
    assert len(sqlpkgs) == len(originalsqlpkgs) + 2

    version = pyexecutor.execute_function_in_sql(check_version)
    assert version == "2.2.2"
    assert version > oldversion

    pkgmanager.uninstall("cryptography")
    pkgmanager.uninstall("asn1crypto")

    sqlpkgs = _get_sql_package_table(connection)
    assert len(sqlpkgs) == len(originalsqlpkgs)


# TODO: more tests for drop external library

def test_scope():

    _remove_all_new_packages(pkgmanager)

    package = os.path.join(path_to_packages, "testpackageA-0.0.1.zip")

    def get_location():
        import testpackageA
        return testpackageA.__file__

    _revotesterconnection = sqlmlutils.ConnectionInfo(server="localhost",
                                                      database="AirlineTestDB",
                                                      uid="Tester",
                                                      pwd="FakeT3sterPwd!")
    revopkgmanager = SQLPackageManager(_revotesterconnection)
    revoexecutor = SQLPythonExecutor(_revotesterconnection)

    revopkgmanager.install(package, scope=Scope.private_scope())
    private_location = revoexecutor.execute_function_in_sql(get_location)

    pkg_name = "testpackageA"

    pyexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=False)

    revopkgmanager.uninstall(pkg_name, scope=Scope.private_scope())

    revopkgmanager.install(package, scope=Scope.public_scope())
    public_location = revoexecutor.execute_function_in_sql(get_location)

    assert private_location != public_location
    pyexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=True, class_to_check='ClassA')

    revopkgmanager.uninstall(pkg_name, scope=Scope.public_scope())

    revoexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=False)
    pyexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=False)
