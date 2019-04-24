# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import sqlmlutils
import os
import pytest
from sqlmlutils import SQLPythonExecutor, SQLPackageManager
from sqlmlutils.packagemanagement.scope import Scope
from package_helper_functions import _get_sql_package_table, _get_package_names_list
import io
from contextlib import redirect_stdout

from conftest import connection

def _drop_all_ddl_packages(conn):
    pkgs = _get_sql_package_table(conn)
    for pkg in pkgs:
        try:
            SQLPackageManager(conn)._drop_sql_package(pkg['name'], scope=Scope.private_scope())
        except Exception:
            pass

pyexecutor = SQLPythonExecutor(connection)
pkgmanager = SQLPackageManager(connection)
_drop_all_ddl_packages(connection)


def _package_exists(module_name: str):
    mod = __import__(module_name)
    return mod is not None


def _package_no_exist(module_name: str):
    import pytest
    with pytest.raises(Exception):
        __import__(module_name)
    return True


def test_install_tensorflow_and_keras():
    def use_tensorflow():
        import tensorflow as tf
        node1 = tf.constant(3.0, tf.float32)
        return str(node1.dtype)

    def use_keras():
        import keras

    pkgmanager.install("tensorflow==1.1.0")
    val = pyexecutor.execute_function_in_sql(use_tensorflow)
    assert 'float32' in val

    pkgmanager.install("keras")
    pyexecutor.execute_function_in_sql(use_keras)
    pkgmanager.uninstall("keras")
    val = pyexecutor.execute_function_in_sql(_package_no_exist, "keras")
    assert val

    pkgmanager.uninstall("tensorflow")
    val = pyexecutor.execute_function_in_sql(_package_no_exist, "tensorflow")
    assert val

    _drop_all_ddl_packages(connection)


def test_install_many_packages():
    packages = ["multiprocessing_on_dill", "simplejson"]

    for package in packages:
        pkgmanager.install(package, upgrade=True)
        val = pyexecutor.execute_function_in_sql(_package_exists, module_name=package)
        assert val

        pkgmanager.uninstall(package)
        val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=package)
        assert val

        _drop_all_ddl_packages(connection)


def test_install_version():
    package = "simplejson"
    v = "3.0.3"

    def _package_version_exists(module_name: str, version: str):
        mod = __import__(module_name)
        return mod.__version__ == version

    pkgmanager.install(package, version=v)
    val = pyexecutor.execute_function_in_sql(_package_version_exists, module_name=package, version=v)
    assert val

    pkgmanager.uninstall(package)
    val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=package)
    assert val

    _drop_all_ddl_packages(connection)


def test_dependency_resolution():
    package = "multiprocessing_on_dill"

    pkgmanager.install(package, upgrade=True)
    val = pyexecutor.execute_function_in_sql(_package_exists, module_name=package)
    assert val

    pkgs = _get_package_names_list(connection)

    assert package in pkgs
    assert "pyreadline" in pkgs

    pkgmanager.uninstall(package)
    val = pyexecutor.execute_function_in_sql(_package_no_exist, module_name=package)
    assert val

    _drop_all_ddl_packages(connection)


def test_upgrade_parameter():

    pkg = "cryptography"

    # Get sql packages
    originalsqlpkgs = _get_sql_package_table(connection)

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

    afterinstall = _get_sql_package_table(connection)
    assert len(afterinstall) > len(originalsqlpkgs)

    version = pyexecutor.execute_function_in_sql(check_version)
    assert version > oldversion

    pkgmanager.uninstall("cryptography")

    sqlpkgs = _get_sql_package_table(connection)
    assert len(sqlpkgs) == len(afterinstall) - 1

    _drop_all_ddl_packages(connection)


def test_install_abslpy():
    pkgmanager.install("absl-py")

    def useit():
        import absl
        return absl.__file__

    pyexecutor.execute_function_in_sql(useit)

    pkgmanager.uninstall("absl-py")

    def dontuseit():
        import pytest
        with pytest.raises(Exception):
            import absl

    pyexecutor.execute_function_in_sql(dontuseit)

    _drop_all_ddl_packages(connection)


@pytest.mark.skip(reason="Theano depends on a conda package libpython? lazylinker issue")
def test_install_theano():
    pkgmanager.install("Theano")

    def useit():
        import theano.tensor as T
        return str(T)

    pyexecutor.execute_function_in_sql(useit)

    pkgmanager.uninstall("Theano")

    pkgmanager.install("theano")
    pyexecutor.execute_function_in_sql(useit)
    pkgmanager.uninstall("theano")

    _drop_all_ddl_packages(connection)


def test_already_installed_popular_ml_packages():
    installedpackages = ["numpy", "scipy", "pandas", "matplotlib", "seaborn", "bokeh", "nltk", "statsmodels"]

    sqlpkgs = _get_sql_package_table(connection)
    for package in installedpackages:
        pkgmanager.install(package)
        newsqlpkgs = _get_sql_package_table(connection)
        assert len(sqlpkgs) == len(newsqlpkgs)


def test_installing_popular_ml_packages():
    newpackages = ["plotly", "cntk", "gensim"]

    def checkit(pkgname):
        val = __import__(pkgname)
        return str(val)

    for package in newpackages:
        pkgmanager.install(package)
        pyexecutor.execute_function_in_sql(checkit, pkgname=package)

    _drop_all_ddl_packages(connection)


# TODO: find a bad pypi package to test this scenario
def test_install_bad_pypi_package():
    pass

