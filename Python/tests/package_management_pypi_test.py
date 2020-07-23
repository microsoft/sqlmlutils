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

@pytest.mark.skip(reason="No version of tensorflow works with currently installed numpy (1.15.4)")
def test_install_tensorflow():
    def use_tensorflow():
        import tensorflow as tf
        node1 = tf.constant(3.0, tf.float32)
        return str(node1.dtype)
    
    try:
        pkgmanager.install("tensorflow", upgrade=True)
        val = pyexecutor.execute_function_in_sql(use_tensorflow)
        assert 'float32' in val

        pkgmanager.uninstall("tensorflow")
        val = pyexecutor.execute_function_in_sql(_package_no_exist, "tensorflow")
        assert val
    finally:
        _drop_all_ddl_packages(connection, scope)


def test_install_many_packages():
    packages = ["multiprocessing_on_dill", "simplejson"]
    
    try:
        for package in packages:
            pkgmanager.install(package, upgrade=True)
            val = pyexecutor.execute_function_in_sql(_package_exists, module_name=package)
            assert val

            pkgmanager.uninstall(package)
            val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=package)
            assert val
    finally:
        _drop_all_ddl_packages(connection, scope)


def test_install_version():
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
    package = "latex"

    try:
        pkgmanager.install(package, upgrade=True)
        val = pyexecutor.execute_function_in_sql(_package_exists, module_name=package)
        assert val

        pkgs = _get_package_names_list(connection)

        assert package in pkgs
        assert "funcsigs" in pkgs

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


@pytest.mark.skipif(sys.platform.startswith("linux"), reason="Managed Instance has a bug with this test, don't run in Travis-CI (which uses Linux)")
def test_install_abslpy():
    def useit():
        import absl
        return absl.__file__

    def dontuseit():
        import pytest
        with pytest.raises(Exception):
            import absl
        
    try:
        pkgmanager.install("absl-py==0.9.0")

        pyexecutor.execute_function_in_sql(useit)

        pkgmanager.uninstall("absl-py")

        pyexecutor.execute_function_in_sql(dontuseit)

    finally:
        _drop_all_ddl_packages(connection, scope)


def test_install_theano():
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


def test_already_installed_popular_ml_packages():
    installedpackages = ["numpy", "scipy", "pandas", "matplotlib", "seaborn", "bokeh", "nltk", "statsmodels"]

    sqlpkgs = _get_sql_package_table(connection)
    for package in installedpackages:
        pkgmanager.install(package)
        newsqlpkgs = _get_sql_package_table(connection)
        assert len(sqlpkgs) == len(newsqlpkgs)

@pytest.mark.skipif(sys.platform.startswith("linux"), reason="Slow test, don't run on Travis-CI, which uses Linux")
def test_installing_popular_ml_packages():
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


# TODO: find a bad pypi package to test this scenario
def test_install_bad_pypi_package():
    pass

