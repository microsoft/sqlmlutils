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

def test_install_abslpy():
    def useit():
        import absl
        return absl.__file__

    try:
        pkgmanager.install("absl-py")
        pyexecutor.execute_function_in_sql(useit)
		
        pkgmanager.uninstall("absl-py")
        with pytest.raises(Exception):
            pyexecutor.execute_function_in_sql(useit)
    finally:
        _drop_all_ddl_packages(connection, scope)
