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

def _drop_all_ddl_packages(conn, scope):
    pkgs = _get_sql_package_table(conn)
    if(len(pkgs.index) > 0 ):
        for pkg in pkgs['name']:
            if pkg not in initial_list:
                try:
                    SQLPackageManager(conn)._drop_sql_package(pkg, scope=scope)
                except Exception as e:
                    pass

def _get_initial_list(conn, scope):
    pkgs = _get_sql_package_table(conn)
    return pkgs['name']

pyexecutor = SQLPythonExecutor(connection)
pkgmanager = SQLPackageManager(connection)
initial_list = _get_sql_package_table(connection)['name']

def _package_exists(module_name: str):
    mod = __import__(module_name)
    return mod is not None


def _package_no_exist(module_name: str):
    import pytest
    with pytest.raises(Exception):
        __import__(module_name)
    return True


def test_install_one_package():
    pkgmanager.install("Theano")

    def useit():
        import theano.tensor as T
        return str(T)

    try:
        pyexecutor.execute_function_in_sql(useit)

        pkgmanager.uninstall("Theano")

        pkgmanager.install("theano==1.0.4")
        pyexecutor.execute_function_in_sql(useit)
        pkgmanager.uninstall("theano")

    finally:
        _drop_all_ddl_packages(connection, scope)

def test_install_version_param():
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


def test_dependency_resolution():
    package = "cryptography"
    version = "2.8"
    dep_package = "pycparser"

    try:
        original_pkgs = _get_package_names_list(connection)
        assert package not in pkgs
        assert dep_package not in pkgs

        pkgmanager.install(package, version=version, upgrade=True)
        val = pyexecutor.execute_function_in_sql(_package_exists, module_name=package)
        assert val

        pkgs = _get_package_names_list(connection)

        assert package in pkgs
        assert dep_package in pkgs

        pkgmanager.uninstall(package)
        val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=package)
        assert val

    finally:
        _drop_all_ddl_packages(connection, scope)


def test_upgrade_parameter():
    try:
        pkg = "cryptography"

        first_version = "2.7"
        second_version = "2.8"
        
        # Install package first so we can test upgrade param
        pkgmanager.install(pkg, version=first_version)
        
        # Get sql packages
        originalsqlpkgs = _get_sql_package_table(connection)

        output = io.StringIO()
        with redirect_stdout(output):
            pkgmanager.install(pkg, upgrade=False, version=second_version)
        assert "exists on server. Set upgrade to True" in output.getvalue()

        # Make sure nothing excess was accidentally installed

        sqlpkgs = _get_sql_package_table(connection)
        assert len(sqlpkgs) == len(originalsqlpkgs)

        #################

        def check_version():
            import cryptography as cp
            return cp.__version__

        oldversion = pyexecutor.execute_function_in_sql(check_version)

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


def test_install_many_packages():
    packages = [("Markdown","2.6.11"), ("simplejson", "3.0.3")]
    
    try:
        for package, version in packages:
            pkgmanager.install(package, version=version, upgrade=True)
            val = pyexecutor.execute_function_in_sql(_package_exists, module_name=package)
            assert val

            pkgmanager.uninstall(package)
            val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=package)
            assert val
    finally:
        _drop_all_ddl_packages(connection, scope)


def test_already_installed_packages():
    installedpackages = ["numpy", "scipy", "pandas"]

    sqlpkgs = _get_sql_package_table(connection)
    for package in installedpackages:
        pkgmanager.install(package)
        newsqlpkgs = _get_sql_package_table(connection)
        assert len(sqlpkgs) == len(newsqlpkgs)