# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import pytest
from contextlib import redirect_stdout, redirect_stderr
import io
import os

from sqlmlutils import SQLPythonExecutor
from sqlmlutils import ConnectionInfo
from pandas import DataFrame
from conftest import driver, server, database, uid, pwd

connection = ConnectionInfo(driver=driver,
                            server=server,
                            database=database,
                            uid=uid,
                            pwd=pwd)

current_dir = os.path.dirname(__file__)
script_dir = os.path.join(current_dir, "scripts")

print(connection)
sqlpy = SQLPythonExecutor(connection)


def test_with_named_args():
    def func_with_args(arg1, arg2):
        print(arg1)
        return arg2

    output = io.StringIO()
    with redirect_stderr(output), redirect_stdout(output):
        res = sqlpy.execute_function_in_sql(func_with_args, arg1="str1", arg2="str2")

    assert "str1" in output.getvalue()
    assert res == "str2"


def test_with_order_args():
    def func_with_order_args(arg1: int, arg2: float):
        return arg1 / arg2

    res = sqlpy.execute_function_in_sql(func_with_order_args, 2, 3.0)
    assert res == 2 / 3.0
    res = sqlpy.execute_function_in_sql(func_with_order_args, 3.0, 2)
    assert res == 3 / 2.0


def test_return():
    def func_with_return():
        return "returned!"

    res = sqlpy.execute_function_in_sql(func_with_return)
    assert res == func_with_return()


@pytest.mark.skip(reason="Do we capture warnings?")
def test_warning():
    def func_with_warning():
        import warnings
        warnings.warn("WARNING!")

    res = sqlpy.execute_function_in_sql(func_with_warning)
    assert res is None


def test_with_internal_func():
    def func_with_internal_func():
        def func2(arg1, arg2):
            return arg1 + arg2

        return func2("Suc", "cess")

    res = sqlpy.execute_function_in_sql(func_with_internal_func)
    assert res == "Success"


@pytest.mark.skip(reason="Cannot currently return a function")
def test_return_func():
    def func2(arg1, arg2):
        return arg1 + arg2

    def func_returns_func():
        def func2(arg1, arg2):
            return arg1 + arg2

        return func2

    res = sqlpy.execute_function_in_sql(func_returns_func)
    assert res == func2


@pytest.mark.skip(reason="Cannot currently return a function outside of environment")
def test_return_func():
    def func2(arg1, arg2):
        return arg1 + arg2

    def func_returns_func():
        return func2

    res = sqlpy.execute_function_in_sql(func_returns_func)
    assert res == func2


def test_with_no_args():
    def func_with_no_args():
        return

    res = sqlpy.execute_function_in_sql(func_with_no_args)

    assert res is None


def test_with_data_frame():
    def func_return_df(in_df):
        return in_df

    res = sqlpy.execute_function_in_sql(func_return_df,
                                        input_data_query="SELECT TOP 10 * FROM airline5000")

    assert type(res) == DataFrame
    assert res.shape == (10, 30)


def test_with_variables():
    def func_with_variables(s):
        print(s)

    output = io.StringIO()
    with redirect_stderr(output), redirect_stdout(output):
        sqlpy.execute_function_in_sql(func_with_variables, s="Hello")

    assert "Hello" in output.getvalue()

    output = io.StringIO()
    with redirect_stderr(output), redirect_stdout(output):
        var_s = "World"
        sqlpy.execute_function_in_sql(func_with_variables, s=var_s)

    assert "World" in output.getvalue()


def test_execute_query():
    res = sqlpy.execute_sql_query("SELECT TOP 10 * FROM airline5000")

    assert type(res) == DataFrame
    assert res.shape == (10, 30)


def test_execute_script():
    path = os.path.join(script_dir, "test_script.py")

    output = io.StringIO()
    with redirect_stderr(output), redirect_stdout(output):
        res = sqlpy.execute_script_in_sql(path_to_script=path,
                                          input_data_query="SELECT TOP 10 * FROM airline5000")

    assert "HelloWorld" in output.getvalue()
    assert res is None

    with pytest.raises(FileNotFoundError):
        sqlpy.execute_script_in_sql(path_to_script="NonexistentScriptPath",
                                    input_data_query="SELECT TOP 10 * FROM airline5000")


def test_stderr():
    def print_to_stderr():
        import sys
        sys.stderr.write("Error!")

    output = io.StringIO()
    with redirect_stderr(output), redirect_stdout(output):
        sqlpy.execute_function_in_sql(print_to_stderr)

    assert "Error!" in output.getvalue()
