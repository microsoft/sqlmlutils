# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import io
import os
import pytest
import sqlmlutils

from contextlib import redirect_stdout
from subprocess import Popen, PIPE, STDOUT
from pandas import DataFrame, set_option

from conftest import connection

current_dir = os.path.dirname(__file__)
script_dir = os.path.join(current_dir, "scripts")
sqlpy = sqlmlutils.SQLPythonExecutor(connection)

# Prevent truncation of DataFrame when printing 
#
set_option("display.max_colwidth", None)
set_option("display.max_columns", None)


###################
# No output tests #
###################

def test_no_output():
    """Test a function without output param/dataset"""
    def my_func():
        print("blah blah blah")
        
        # Test single quotes as well
        #
        print('Hello')

    name = "test_no_output"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, my_func)
    assert sqlpy.check_sproc(name)

    x, outparams = sqlpy.execute_sproc(name)
    assert type(x) == DataFrame
    assert x.empty
    assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_no_output_mixed_args():
    """Test a function without output, with mixed input parameters"""
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
    """Test a function without output, with mixed input parameters and with input data set"""
    def mixed(val1: int, val2: str, val3: float, val4: bool, val5: DataFrame):
        # Prevent truncation of DataFrame when printing
        #
        import pandas as pd
        pd.set_option("display.max_colwidth", -1)
        pd.set_option("display.max_columns", None)
        
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
    """Test a function without output, with input parameters specified (not implicit)"""
    def mixed(val1: int, val2: str, val3: float, val4: bool, val5: DataFrame):
        # Prevent truncation of DataFrame when printing
        #
        import pandas as pd
        pd.set_option("display.max_colwidth", -1)
        pd.set_option("display.max_columns", None)
        
        print(val1, val2, val3, val4)
        print(val5)

    in_params = {"val1": int, "val2": str, "val3": float, "val4": bool, "val5": DataFrame}
    name = "test_no_output_mixed_args_in_df_in_params"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name=name, func=mixed, input_params=in_params)
    
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


################
# Test outputs #
################

def test_out_df_no_params():
    """Test a function with output data set but no parameters"""
    def no_params():
        df = DataFrame()
        df["col1"] = [1, 2, 3, 4, 5]
        return df

    name = "test_out_df_no_params"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, no_params)
    assert sqlpy.check_sproc(name)

    df, outparams = sqlpy.execute_sproc(name)
    assert list(df.iloc[:,0] == [1, 2, 3, 4, 5])
    assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_with_args():
    """Test a function with output data set and input args"""
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
        res, outparams = sqlpy.execute_sproc(name, arg1=arg1, arg2=arg2)
        assert res.loc[0].iloc[0] == arg1
        assert res.loc[0].iloc[1] == arg2
        assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_in_df():
    """Test a function with input and output data set"""
    def in_data(in_df: DataFrame):
        return in_df

    name = "test_out_df_in_df"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, in_data)
    assert sqlpy.check_sproc(name)

    res, outparams = sqlpy.execute_sproc(name, in_df="SELECT TOP 10 * FROM airline5000")

    assert type(res) == DataFrame
    assert res.shape == (10, 30)
    assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_mixed_args_in_df():
    """Test a function with input, output data set and input params"""
    def mixed(val1: int, val2: str, val3: float, val4: DataFrame, val5: bool):
        # Prevent truncation of DataFrame when printing
        #
        import pandas as pd
        pd.set_option("display.max_colwidth", -1)
        pd.set_option("display.max_columns", None)
        
        print(val1, val2, val3, val5)
        
        if val5 and val1 == 5 and val2 == "blah" and val3 == 15.5:
            return val4
        else:
            return None

    name = "test_out_df_mixed_args_in_df"
    sqlpy.drop_sproc(name)

    sqlpy.create_sproc_from_function(name, mixed)

    res, outparams = sqlpy.execute_sproc(name, val1=5, val2="blah", val3=15.5,
                              val4="SELECT TOP 10 * FROM airline5000", val5=True)

    assert type(res) == DataFrame
    assert res.shape == (10, 30)
    assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_df_mixed_in_params_in_df():
    """Test a function with input, output data set and specified input params"""
    def mixed(val1, val2, val3, val4, val5):
        # Prevent truncation of DataFrame when printing
        #
        import pandas as pd
        pd.set_option("display.max_colwidth", -1)
        pd.set_option("display.max_columns", None)
        
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

    res, outparams = sqlpy.execute_sproc(name, val1=5, val2="blah", val3=15.5,
                              val4="SELECT TOP 10 * FROM airline5000", val5=True)

    assert type(res) == DataFrame
    assert res.shape == (10, 30)
    assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_out_of_order_args():
    """Test a function with specified input params and out of order named params"""
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
    res, outparams = sqlpy.execute_sproc(name, val5=False, val3=v3, val4=v4, val1=v1, val2=v2)

    assert res.loc[0].iloc[0] == v1
    assert res.loc[0].iloc[1] == v2
    assert res.loc[0].iloc[2] == v3
    assert not res.loc[0].iloc[3]
    assert not outparams
    
    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_in_param_out_param():
    """Test a function with input and output params"""
    def in_out(t1, t2, t3):
        # Prevent truncation of DataFrame when printing
        #
        import pandas as pd
        pd.set_option("display.max_colwidth", -1)
        pd.set_option("display.max_columns", None)
        
        print(t2)
        print(t3)
        param_str = "Hello " + t1
        return {"out_df": t3, "param_str": param_str}

    name = "test_in_param_out_param"
    sqlpy.drop_sproc(name)

    input_params = {"t1": str, "t2": int, "t3": DataFrame}
    output_params = {"param_str": str, "out_df": DataFrame}

    sqlpy.create_sproc_from_function(name, in_out, input_params=input_params, output_params=output_params)
    assert sqlpy.check_sproc(name)

    res, outparams = sqlpy.execute_sproc(name, output_params = output_params, t1="Hello", t2 = 213, t3 = "select top 10 * from airline5000")
    assert "Hello Hello" in outparams["param_str"]

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_in_df_out_df_dict():
    """Test a function with input and output data set, but as dictionary not DataFrame"""
    def func(in_df: DataFrame):
        return {"out_df": in_df}

    name = "test_in_df_out_df_dict"
    sqlpy.drop_sproc(name)

    output_params = {"out_df": DataFrame}

    sqlpy.create_sproc_from_function(name, func, output_params=output_params)
    assert sqlpy.check_sproc(name)

    res, outparams = sqlpy.execute_sproc(name, in_df="SELECT TOP 10 * FROM airline5000")

    assert type(res) == DataFrame
    assert res.shape == (10, 30)
    assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


################
# Script Tests #
################

def test_script_no_params():
    """Test a script with no params, with print output"""
    script = os.path.join(script_dir, "exec_script_no_params.py")

    name = "exec_script_no_params"
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
    """Test a script with input params, with print output"""
    script = os.path.join(script_dir, "exec_script_no_out_params.py")

    name = "exec_script_no_out_params"
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
    """Test a script with an output data set"""
    script = os.path.join(script_dir, "exec_script_sproc_out_df.py")

    name = "exec_script_out_df"
    sqlpy.drop_sproc(name)

    input_params = {"t1": str, "t2": int, "t3": DataFrame}

    sqlpy.create_sproc_from_script(name, script, input_params)
    assert sqlpy.check_sproc(name)

    res, outparams = sqlpy.execute_sproc(name, t1="Hello", t2=2313, t3="SELECT TOP 10 * FROM airline5000")
    
    assert type(res) == DataFrame
    assert res.shape == (10, 30)
    assert not outparams

    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


def test_script_out_param():
    """Test a script with output params"""
    script = os.path.join(script_dir, "exec_script_out_param.py")

    name = "exec_script_out_param"
    sqlpy.drop_sproc(name)

    input_params = {"t1": str, "t2": int, "t3": DataFrame}
    output_params = {"param_str": str}

    sqlpy.create_sproc_from_script(name, script, input_params, output_params)
    assert sqlpy.check_sproc(name)
    
    res, outparams = sqlpy.execute_sproc(name, output_params = output_params, t1="Hello", t2 = 123, t3 = "select top 10 * from airline5000")
    assert "Hello123" in outparams["param_str"]
        
    sqlpy.drop_sproc(name)
    assert not sqlpy.check_sproc(name)


##################
# Negative Tests #
##################

def test_execute_bad_param_types():
    """Test functions with unsupported or mismatched inputs"""
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

    sqlpy.drop_sproc(name)


def test_create_bad_name():
    """Test creating a sproc with an unsupported name"""
    def foo():
        return 1
    with pytest.raises(RuntimeError):
        sqlpy.create_sproc_from_function("'''asd''asd''asd", foo)


def test_no_output_bad_num_args():
    """Test function with incorrect, untyped, or unmatched input params"""
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
    """Test function with annotations that don't match input params"""
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
    """Test nonexistent script"""
    with pytest.raises(FileNotFoundError):
        sqlpy.create_sproc_from_script(name="badScript", path_to_script="NonexistentScriptPath")

