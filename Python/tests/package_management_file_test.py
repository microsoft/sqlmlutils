# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import io
import os
import sys
import subprocess
import tempfile
from contextlib import redirect_stdout

import pytest

from sqlmlutils import ConnectionInfo, SQLPackageManager, SQLPythonExecutor, Scope
from package_helper_functions import _get_sql_package_table, _get_package_names_list
from sqlmlutils.packagemanagement.pipdownloader import PipDownloader

from conftest import connection, airline_user_connection

path_to_packages = os.path.join((os.path.dirname(os.path.realpath(__file__))), "scripts", "test_packages")
_SUCCESS_TOKEN = "SUCCESS"

pyexecutor = SQLPythonExecutor(connection)
pkgmanager = SQLPackageManager(connection)

originals = _get_sql_package_table(connection)

def check_package(package_name: str, exists: bool, class_to_check: str = ""):
    """Check and assert whether a package exists, and if a class is in the module"""
    if exists:
        themodule = __import__(package_name)
        assert themodule is not None
        assert getattr(themodule, class_to_check) is not None
    else:
        import pytest
        with pytest.raises(Exception):
            __import__(package_name)

def _drop(package_name: str, ddl_name: str):
    """Uninstall a package and check that it is gone"""
    pkgmanager.uninstall(package_name)
    pyexecutor.execute_function_in_sql(check_package, package_name=package_name, exists=False)

def _create(module_name: str, package_file: str, class_to_check: str, drop: bool = True):
    """Install a package and check that it is installed"""
    try:
        pyexecutor.execute_function_in_sql(check_package, package_name=module_name, exists=False)
        pkgmanager.install(package_file)
        pyexecutor.execute_function_in_sql(check_package, package_name=module_name, exists=True, class_to_check=class_to_check)
    finally:
        if drop:
            _drop(package_name=module_name, ddl_name=module_name)

def _remove_all_new_packages(manager):
    """Drop all packages that were not there in the original list"""
    df = _get_sql_package_table(connection)
    
    libs = {df['external_library_id'][i]: (df['name'][i], df['scope'][i]) for i in range(len(df.index))}
    original_libs = {originals['external_library_id'][i]: (originals['name'][i], originals['scope'][i]) for i in range(len(originals.index))}

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


# Download the package zips we will use for these tests
# 
packages = ["astor==0.8.1", "html5lib==1.0.1", "termcolor==1.1.0"]

for package in packages:
    pipdownloader = PipDownloader(connection, path_to_packages, package, language_name="Python")
    pipdownloader.download_single()

def test_install_basic_zip_package():
    """Test a basic zip package"""
    package = os.path.join(path_to_packages, "testpackageA-0.0.1.zip")
    module_name = "testpackageA"

    _remove_all_new_packages(pkgmanager)

    _create(module_name=module_name, package_file=package, class_to_check="ClassA")

def test_install_whl_files():
    """Test some basic wheel files"""
    packages = ["html5lib-1.0.1-py2.py3-none-any.whl",
                "astor-0.8.1-py2.py3-none-any.whl"]
    module_names = ["html5lib", "astor"]
    classes_to_check = ["parse", "code_gen"]

    _remove_all_new_packages(pkgmanager)

    for package, module, class_to_check in zip(packages, module_names, classes_to_check):
        full_package = os.path.join(path_to_packages, package)
        _create(module_name=module, package_file=full_package, class_to_check=class_to_check)


def test_install_targz_files():
    """Test a basic tar.gz file"""
    packages = ["termcolor-1.1.0.tar.gz"]
    module_names = ["termcolor"]
    ddl_names = ["termcolor"]
    classes_to_check = ["colored"]

    _remove_all_new_packages(pkgmanager)

    for package, module, ddl_name, class_to_check in zip(packages, module_names, ddl_names, classes_to_check):
        full_package = os.path.join(path_to_packages, package)
        _create(module_name=module, package_file=full_package, class_to_check=class_to_check)

def test_install_bad_package_badzipfile():
    """Test a zip that is not a package, then make sure it is not in the external_libraries table"""
    _remove_all_new_packages(pkgmanager)

    with tempfile.TemporaryDirectory() as temporary_directory:
        badpackagefile = os.path.join(temporary_directory, "badpackageA-0.0.1.zip")
        with open(badpackagefile, "w") as f:
            f.write("asdasdasdascsacsadsadas")
        with pytest.raises(Exception):
            pkgmanager.install(badpackagefile)

        assert "badpackageA" not in _get_package_names_list(connection)

def test_package_already_exists_on_sql_table():
    """Test the 'upgrade' parameter in installation"""
    _remove_all_new_packages(pkgmanager)

    # Install a downgraded version of the package first
    #
    package = os.path.join(path_to_packages, "testpackageA-0.0.1.zip")
    pkgmanager.install(package)
    
    def check_version():
        import pkg_resources
        return pkg_resources.get_distribution("testpackageA").version

    version = pyexecutor.execute_function_in_sql(check_version)
    assert version == "0.0.1"
    
    package = os.path.join(path_to_packages, "testpackageA-0.0.2.zip")

    # Without upgrade
    #
    output = io.StringIO()
    with redirect_stdout(output):
        pkgmanager.install(package, upgrade=False)
    assert "exists on server. Set upgrade to True" in output.getvalue()

    version = pyexecutor.execute_function_in_sql(check_version)
    assert version == "0.0.1"
    
    # With upgrade
    #
    pkgmanager.install(package, upgrade=True)

    version = pyexecutor.execute_function_in_sql(check_version)
    assert version == "0.0.2"

    pkgmanager.uninstall("testpackageA")


def test_scope():
    """Test installing in a private scope with a db_owner (not dbo) user"""
    _remove_all_new_packages(pkgmanager)

    package = os.path.join(path_to_packages, "testpackageA-0.0.1.zip")

    def get_location():
        import testpackageA
        return testpackageA.__file__

    # The airline_user_connection is NOT dbo, so it has access to both Private and Public scopes
    # 
    revopkgmanager = SQLPackageManager(airline_user_connection)
    revoexecutor = SQLPythonExecutor(airline_user_connection)

    # Install a package into the private scope
    #
    revopkgmanager.install(package, scope=Scope.private_scope())
    private_location = revoexecutor.execute_function_in_sql(get_location)

    pkg_name = "testpackageA"

    pyexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=False)

    revopkgmanager.uninstall(pkg_name, scope=Scope.private_scope())

    # Try the same installation in public scope
    #
    revopkgmanager.install(package, scope=Scope.public_scope())
    public_location = revoexecutor.execute_function_in_sql(get_location)

    assert private_location != public_location
    pyexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=True, class_to_check='ClassA')

    revopkgmanager.uninstall(pkg_name, scope=Scope.public_scope())

    # Make sure the package was removed properly
    #
    revoexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=False)
    pyexecutor.execute_function_in_sql(check_package, package_name=pkg_name, exists=False)
