# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import io
import os
import sys
import pytest

from contextlib import redirect_stdout
from package_helper_functions import _get_sql_package_table, _get_package_names_list
from sqlmlutils import SQLPythonExecutor, SQLPackageManager, Scope

from conftest import connection, scope

pyexecutor = SQLPythonExecutor(connection)
pkgmanager = SQLPackageManager(connection)
initial_list = _get_sql_package_table(connection)['name']

def _drop_all_ddl_packages(conn, scope):
    """Clean the external libraries - drop all packages"""
    pkgs = _get_sql_package_table(conn)
    if(len(pkgs.index) > 0 ):
        for pkg in pkgs['name']:
            if pkg not in initial_list:
                try:
                    SQLPackageManager(conn)._drop_sql_package(pkg, scope=scope)
                except Exception as e:
                    pass

def _package_exists(module_name: str):
    """Check if a package exists"""
    mod = __import__(module_name)
    return mod is not None

def _package_no_exist(module_name: str):
    """Check that a package does NOT exist"""
    import pytest
    with pytest.raises(Exception):
        __import__(module_name)
    return True
    
    
def test_install_different_names():
    """Test installing a single package with different capitalization"""
    def useit():
        import theano.tensor as T
        return str(T)

    try:
        pkgmanager.install("Theano==1.0.4")
        pyexecutor.execute_function_in_sql(useit)

        pkgmanager.uninstall("Theano")

        pkgmanager.install("theano==1.0.4")
        pyexecutor.execute_function_in_sql(useit)
        pkgmanager.uninstall("theano")

    finally:
        _drop_all_ddl_packages(connection, scope)

def test_install_version():
    """Test the 'version' installation parameter"""
    package = "simplejson"
    v = "3.0.3"

    def _package_version_exists(module_name: str, version: str):
        mod = __import__(module_name)
        return mod.__version__ == version

    try:
        pkgmanager.install(package, version=v)
        val = pyexecutor.execute_function_in_sql(_package_version_exists, module_name=package, version=v)
        assert val

        pkgmanager.uninstall(package)
        val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=package)
        assert val
    finally:
        _drop_all_ddl_packages(connection, scope)

@pytest.mark.skipif(sys.platform.startswith("linux"), reason="Slow test, don't run on Travis-CI, which uses Linux")
def test_no_upgrade_parameter():
    """Test new version but no "upgrade" installation parameter"""
    try:
        pkg = "cryptography"

        first_version = "2.7"
        second_version = "2.8"
        
        # Install package first so we can test upgrade param
        #
        pkgmanager.install(pkg, version=first_version)
        
        # Get sql packages
        #
        originalsqlpkgs = _get_sql_package_table(connection)

        # Try installing WITHOUT the upgrade parameter, it should fail
        #
        output = io.StringIO()
        with redirect_stdout(output):
            pkgmanager.install(pkg, upgrade=False, version=second_version)
        assert "exists on server. Set upgrade to True" in output.getvalue()

        # Make sure nothing excess was accidentally installed
        #
        sqlpkgs = _get_sql_package_table(connection)
        assert len(sqlpkgs) == len(originalsqlpkgs)

    finally:
        _drop_all_ddl_packages(connection, scope)


@pytest.mark.skipif(sys.platform.startswith("linux"), reason="Slow test, don't run on Travis-CI, which uses Linux")
def test_upgrade_parameter():
    """Test the "upgrade" installation parameter"""
    try:
        pkg = "cryptography"

        first_version = "2.7"
        second_version = "2.8"
        
        # Install package first so we can test upgrade param
        #
        pkgmanager.install(pkg, version=first_version)
        
        # Get sql packages
        #
        originalsqlpkgs = _get_sql_package_table(connection)
        
        def check_version():
            import cryptography as cp
            return cp.__version__

        oldversion = pyexecutor.execute_function_in_sql(check_version)

        # Test installing WITH the upgrade parameter
        #
        pkgmanager.install(pkg, upgrade=True, version=second_version)

        afterinstall = _get_sql_package_table(connection)
        assert len(afterinstall) >= len(originalsqlpkgs)

        version = pyexecutor.execute_function_in_sql(check_version)
        assert version > oldversion

        pkgmanager.uninstall("cryptography")

        sqlpkgs = _get_sql_package_table(connection)
        assert len(sqlpkgs) == len(afterinstall) - 1

    finally:
        _drop_all_ddl_packages(connection, scope)

@pytest.mark.skipif(sys.platform.startswith("linux"), reason="Slow test, don't run on Travis-CI, which uses Linux")
def test_already_installed_popular_ml_packages():
    """Test packages that are preinstalled, make sure they do not install anything extra"""
    installedpackages = ["numpy", "scipy", "pandas"]

    sqlpkgs = _get_sql_package_table(connection)
    for package in installedpackages:
        pkgmanager.install(package)
        newsqlpkgs = _get_sql_package_table(connection)
        assert len(sqlpkgs) == len(newsqlpkgs)

@pytest.mark.skipif(sys.platform.startswith("linux"), reason="Slow test, don't run on Travis-CI, which uses Linux")
def test_dependency_spec():
    """Test that the DepedencyResolver handles ~= requirement spec.
    Also tests when package name and module name are different."""
    package = "azure_cli_telemetry"
    version = "1.0.4"
    dependent = "portalocker"
    module = "azure"

    try:
        # Install the package and its dependencies
        #
        pkgmanager.install(package, version=version)
        val = pyexecutor.execute_function_in_sql(_package_exists, module_name=module)
        assert val

        pkgs = _get_package_names_list(connection)

        assert package in pkgs
        assert dependent in pkgs
            
        # Uninstall the top package only, not the dependencies
        #
        pkgmanager.uninstall(package)
        val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=module)
        assert val
        
        pkgs = _get_package_names_list(connection)

        assert package not in pkgs
        assert dependent in pkgs
        
    finally:
        _drop_all_ddl_packages(connection, scope)

@pytest.mark.skipif(sys.platform.startswith("linux"), reason="Slow test, don't run on Travis-CI, which uses Linux")
def test_installing_popular_ml_packages():
    """Test a couple of popular ML packages"""
    newpackages = ["plotly==4.9.0", "gensim==3.8.3"]

    def checkit(pkgname):
        val = __import__(pkgname)
        return str(val)

    try:
        for package in newpackages:
            pkgmanager.install(package)
            pyexecutor.execute_function_in_sql(checkit, pkgname=package)
    finally:
        _drop_all_ddl_packages(connection, scope)

