# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import pytest
import sqlmlutils
from contextlib import redirect_stdout
from subprocess import Popen, PIPE, STDOUT
from pandas import DataFrame
import io
import os

from conftest import connection

current_dir = os.path.dirname(__file__)
script_dir = os.path.join(current_dir, "scripts")
sqlpy = sqlmlutils.SQLPythonExecutor(connection)


###################
# No output tests #
###################

def test_no_output():
    def my_func():
        print("blah blah blah")

    name = "test_no_output"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, my_func)
    assert sqlpy.check_sproc(name)

    x = sqlpy.execute_sproc(name)
    assert type(x) == DataFrame
    assert x.empty

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_no_output_mixed_args():
    def mixed(val1: int, val2: str, val3: float, val4: bool):
        print(val1, val2, val3, val4)

    name = "test_no_output_mixed_args"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, mixed)
    buf = io.StringIO()
    with redirect_stdout(buf):
        sqlpy.execute_sproc(name, val1=5, val2="blah", val3=15.5, val4=True)
    assert "5 blah 15.5 True" in buf.getvalue()

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_no_output_mixed_args_in_df():
    def mixed(val1: int, val2: str, val3: float, val4: bool, val5: DataFrame):
        print(val1, val2, val3, val4)
        print(val5)

    name = "test_no_output_mixed_args_in_df"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, mixed)
    buf = io.StringIO()
    with redirect_stdout(buf):
        sqlpy.execute_sproc(name, val1=5, val2="blah", val3=15.5, val4=False, val5="SELECT TOP 2 * FROM airline5000")
    assert "5 blah 15.5 False" in buf.getvalue()
    assert "ArrTime" in buf.getvalue()
    assert "CRSDepTime" in buf.getvalue()
    assert "DepTime" in buf.getvalue()
    assert "CancellationCode" in buf.getvalue()
    assert "DayOfWeek" in buf.getvalue()

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_no_output_mixed_args_in_df_in_params():
    def mixed(val1, val2, val3, val4, val5):
        print(val1, val2, val3, val5)
        print(val4)

    in_params = {"val1": int, "val2": str, "val3": float, "val4": DataFrame, "val5": bool}
    name = "test_no_output_mixed_args_in_df_in_params"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name=name, func=mixed, input_params=in_params)
    buf = io.StringIO()
    with redirect_stdout(buf):
        sqlpy.execute_sproc(name, val1=5, val2="blah", val3=15.5, val4="SELECT TOP 2 * FROM airline5000", val5=False)
    assert "5 blah 15.5 False" in buf.getvalue()
    assert "ArrTime" in buf.getvalue()
    assert "CRSDepTime" in buf.getvalue()
    assert "DepTime" in buf.getvalue()
    assert "CancellationCode" in buf.getvalue()
    assert "DayOfWeek" in buf.getvalue()

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


################
# Test outputs #
################

def test_out_df_no_params():
    def no_params():
        df = DataFrame()
        df["col1"] = [1, 2, 3, 4, 5]
        return df

    name = "test_out_df_no_params"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, no_params)
    assert sqlpy.check_sproc(name)

    df = sqlpy.execute_sproc(name)
    assert list(df.iloc[:,0] == [1, 2, 3, 4, 5])

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_with_args():
    def my_func_with_args(arg1: str, arg2: str):
        return DataFrame({"arg1": [arg1], "arg2": [arg2]})

    name = "test_out_df_with_args"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, my_func_with_args)
    assert sqlpy.check_sproc(name)

    vals = [("arg1val", "arg2val"), ("asd", "Asd"), ("Qwe", "Qwe"), ("zxc", "Asd")]

    for values in vals:
        arg1 = values[0]
        arg2 = values[1]
        res = sqlpy.execute_sproc(name, arg1=arg1, arg2=arg2)
        assert res[0][0] == arg1
        assert res[1][0] == arg2

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_in_df():
    def in_data(in_df: DataFrame):
        return in_df

    name = "test_out_df_in_df"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, in_data)
    assert sqlpy.check_sproc(name)

    res = sqlpy.execute_sproc(name, in_df="SELECT TOP 10 * FROM airline5000")

    assert type(res) == DataFrame
    assert res.shape == (10, 30)

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_mixed_args_in_df():
    def mixed(val1: int, val2: str, val3: float, val4: DataFrame, val5: bool):
        print(val1, val2, val3, val5)
        if val5 and val1 == 5 and val2 == "blah" and val3 == 15.5:
            return val4
        else:
            return None

    name = "test_out_df_mixed_args_in_df"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, mixed)

    res = sqlpy.execute_sproc(name, val1=5, val2="blah", val3=15.5,
                              val4="SELECT TOP 10 * FROM airline5000", val5=True)

    assert type(res) == DataFrame
    assert res.shape == (10, 30)

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_mixed_in_params_in_df():
    def mixed(val1, val2, val3, val4, val5):
        print(val1, val2, val3, val5)
        if val5 and val1 == 5 and val2 == "blah" and val3 == 15.5:
            return val4
        else:
            return None

    name = "test_out_df_mixed_in_params_in_df"
    sqlpy.drop_sproc(name)

    input_params = {"val1": int, "val2": str, "val3": float, "val4": DataFrame, "val5": bool}

    sqlpy.create_sproc_from_function(name, mixed, input_params=input_params)
    assert sqlpy.check_sproc(name)

    res = sqlpy.execute_sproc(name, val1=5, val2="blah", val3=15.5,
                              val4="SELECT TOP 10 * FROM airline5000", val5=True)

    assert type(res) == DataFrame
    assert res.shape == (10, 30)

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_of_order_args():
    def mixed(val1, val2, val3, val4, val5):
        return DataFrame({"val1": [val1], "val2": [val2], "val3": [val3], "val5": [val5]})

    in_params = {"val2": str, "val3": float, "val5": bool, "val4": DataFrame, "val1": int}

    name = "test_out_of_order_args"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name=name, func=mixed, input_params=in_params)
    assert sqlpy.check_sproc(name)

    v1 = 5
    v2 = "blah"
    v3 = 15.5
    v4 = "SELECT TOP 10 * FROM airline5000"
    res = sqlpy.execute_sproc(name, val5=False, val3=v3, val4=v4, val1=v1, val2=v2)

    assert res[0][0] == v1
    assert res[1][0] == v2
    assert res[2][0] == v3
    assert not res[3][0]

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


# TODO: Output Params execution not currently supported
def test_in_param_out_param():
    def in_out(t1, t2, t3):
        print(t2)
        print(t3)
        res = "Hello " + t1
        return {'out_df': t3, 'res': res}

    name = "test_in_param_out_param"
    sqlpy.drop_sproc(name)

    input_params = {"t1": str, "t2": int, "t3": DataFrame}
    output_params = {"res": str, "out_df": DataFrame}

    sqlpy.create_sproc_from_function(name, in_out, input_params=input_params, output_params=output_params)
    assert sqlpy.check_sproc(name)

    # Out params don't currently work so we use sqlcmd to test the output param sproc
    sql_str = "DECLARE @res nvarchar(max)  EXEC test_in_param_out_param @t2 = 213, @t1 = N'Hello', " \
              "@t3 = N'select top 10 * from airline5000', @res = @res OUTPUT SELECT @res as N'@res'"
    p = Popen(["sqlcmd", "-S", connection.server, "-E", "-d", connection.database, "-Q", sql_str],
              shell=True, stdin=PIPE, stdout=PIPE, stderr=STDOUT)
    output = p.stdout.read()
    assert "Hello Hello" in output.decode()

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_in_df_out_df_dict():
    def func(in_df: DataFrame):
        return {"out_df": in_df}

    name = "test_in_df_out_df_dict"
    sqlpy.drop_sproc(name)

    output_params = {"out_df": DataFrame}

    sqlpy.create_sproc_from_function(name, func, output_params=output_params)
    assert sqlpy.check_sproc(name)

    res = sqlpy.execute_sproc(name, in_df="SELECT TOP 10 * FROM airline5000")

    assert type(res) == DataFrame
    assert res.shape == (10, 30)

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


################
# Script Tests #
################

def test_script_no_params():
    script = os.path.join(script_dir, "test_script_no_params.py")

    name = "test_script_no_params"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_script(name, script)
    assert sqlpy.check_sproc(name)

    buf = io.StringIO()
    with redirect_stdout(buf):
        sqlpy.execute_sproc(name)
    assert "No Inputs" in buf.getvalue()
    assert "Required" in buf.getvalue()
    assert "Testing output!" in buf.getvalue()
    assert "HelloWorld" not in buf.getvalue()

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_script_no_out_params():
    script = os.path.join(script_dir, "test_script_no_out_params.py")

    name = "test_script_no_out_params"
    sqlpy.drop_sproc(name)

    input_params = {"t1": str, "t2": str, "t3": int}

    sqlpy.create_sproc_from_script(name, script, input_params)
    assert sqlpy.check_sproc(name)

    buf = io.StringIO()
    with redirect_stdout(buf):
        sqlpy.execute_sproc(name, t1="Hello", t2="World", t3=312)
    assert "HelloWorld" in buf.getvalue()
    assert "312" in buf.getvalue()
    assert "Testing output!" in buf.getvalue()

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_script_out_df():
    script = os.path.join(script_dir, "test_script_sproc_out_df.py")

    name = "test_script_out_df"
    sqlpy.drop_sproc(name)

    input_params = {"t1": str, "t2": int, "t3": DataFrame}

    sqlpy.create_sproc_from_script(name, script, input_params)
    assert sqlpy.check_sproc(name)

    res = sqlpy.execute_sproc(name, t1="Hello", t2=2313, t3="SELECT TOP 10 * FROM airline5000")

    assert type(res) == DataFrame
    assert res.shape == (10, 30)

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


#TODO: Output Params execution not currently supported
def test_script_out_param():
    script = os.path.join(script_dir, "test_script_out_param.py")

    name = "test_script_out_param"
    sqlpy.drop_sproc(name)

    input_params = {"t1": str, "t2": int, "t3": DataFrame}
    output_params = {"res": str}

    sqlpy.create_sproc_from_script(name, script, input_params, output_params)
    assert sqlpy.check_sproc(name)

    # Out params don't currently work so we use sqlcmd to test the output param sproc
    sql_str = "DECLARE @res nvarchar(max)  EXEC test_script_out_param @t2 = 123, @t1 = N'Hello', " \
              "@t3 = N'select top 10 * from airline5000', @res = @res OUTPUT SELECT @res as N'@res'"
    p = Popen(["sqlcmd", "-S", connection.server, "-E", "-d", connection.database, "-Q", sql_str],
              shell=True, stdin=PIPE, stdout=PIPE, stderr=STDOUT)
    output = p.stdout.read()
    assert "Hello123" in output.decode()

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


##################
# Negative Tests #
##################

def test_execute_bad_param_types():
    def bad_func(input1: bin):
        pass

    with pytest.raises(ValueError):
        sqlpy.create_sproc_from_function("BadParam", bad_func)

    def func(input1: bool):
        pass
    name = "BadInput"
    sqlpy.drop_sproc(name)
    sqlpy.create_sproc_from_function(name, func)
    assert sqlpy.check_sproc(name)

    with pytest.raises(RuntimeError):
        sqlpy.execute_sproc(name, input1="Hello!")


def test_create_bad_name():
    def foo():
        return 1
    with pytest.raises(RuntimeError):
        sqlpy.create_sproc_from_function("'''asd''asd''asd", foo)


def test_no_output_bad_num_args():
    def mixed(val1: str, val2, val3, val4):
        print(val1, val2, val3)
        print(val4)

    name = "test_no_output_bad_num_args"
    sqlpy.drop_sproc(name)

    with pytest.raises(ValueError):
        sqlpy.create_sproc_from_function(name=name, func=mixed)

    def func(val1, val2, val3, val4):
        print(val1, val2, val3)
        print(val4)

    input_params = {"val1": int, "val4": str, "val5": int, "BADVAL": str}
    sqlpy.drop_sproc(name)

    with pytest.raises(ValueError):
        sqlpy.create_sproc_from_function(name=name, func=func, input_params=input_params)

    input_params = {"val1": int, "val2": int, "val3": str}
    sqlpy.drop_sproc(name)

    with pytest.raises(ValueError):
        sqlpy.create_sproc_from_function(name=name, func=func, input_params=input_params)


def test_annotation_vs_input_param():
    def foo(val1: str, val2: int, val3: int):
        print(val1)
        print(val2)
        return val3

    name = "test_input_param_override_error"
    input_params = {"val1": str, "val2": int, "val3": DataFrame}

    sqlpy.drop_sproc(name)
    with pytest.raises(ValueError):
        sqlpy.create_sproc_from_function(name=name, func=foo, input_params=input_params)


def test_bad_script_path():
    with pytest.raises(FileNotFoundError):
        sqlpy.create_sproc_from_script(name="badScript", path_to_script="NonexistentScriptPath")

